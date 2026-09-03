"""Web Admin UI router serving HTML templates and HTMX endpoints."""

from pathlib import Path
from fastapi import APIRouter, Depends, Form, HTTPException, Request, Response, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.application.schema_service import SchemaService
from altr_stream.application.source_service import SourceService
from altr_stream.domain.errors import AltrStreamError, SourceAlreadyExistsError, SourceNotFoundError
from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.database.repository import SqliteSourceRepository
from altr_stream.infrastructure.database.session import get_session

# Configure templates path
TEMPLATES_DIR = Path(__file__).parent / "templates"
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

web_router = APIRouter(include_in_schema=False)


def get_source_service(session: AsyncSession = Depends(get_session)) -> SourceService:
    repository = SqliteSourceRepository(session)
    return SourceService(repository)


def get_schema_service(session: AsyncSession = Depends(get_session)) -> SchemaService:
    repository = SqliteSourceRepository(session)
    return SchemaService(repository)


@web_router.get("/", response_class=HTMLResponse)
async def dashboard(
    request: Request,
    service: SourceService = Depends(get_source_service),
):
    """Admin Dashboard showing all registered sources."""
    sources = await service.list_sources()
    return templates.TemplateResponse(
        request=request,
        name="dashboard.html",
        context={
            "sources": sources,
            "active_page": "dashboard",
        },
    )


@web_router.get("/admin/sources/new", response_class=HTMLResponse)
async def new_source_page(request: Request):
    """Render Add Source page."""
    return templates.TemplateResponse(
        request=request,
        name="source_add.html",
        context={
            "active_page": "add_source",
            "form_data": None,
            "error": None,
        },
    )


@web_router.post("/admin/sources/test-inline", response_class=HTMLResponse)
async def test_inline_connection(
    request: Request,
    type: str = Form("POSTGRESQL"),
    host: str = Form(...),
    port: int = Form(5432),
    database_name: str = Form(...),
    username: str = Form(...),
    password: str = Form(""),
    service: SourceService = Depends(get_source_service),
):
    """HTMX endpoint for testing connection parameters before saving."""
    source_type = SourceType(type)
    config = ConnectionConfig(
        host=host,
        port=port,
        database_name=database_name,
        username=username,
        password=password,
    )
    result = await service.test_adhoc_connection(source_type, config)
    return templates.TemplateResponse(
        request=request,
        name="partials/test_result.html",
        context={
            "result": result,
        },
    )


@web_router.post("/admin/sources/new", response_class=HTMLResponse)
async def create_source_form(
    request: Request,
    name: str = Form(...),
    type: str = Form("POSTGRESQL"),
    host: str = Form(...),
    port: int = Form(5432),
    database_name: str = Form(...),
    username: str = Form(...),
    password: str = Form(...),
    service: SourceService = Depends(get_source_service),
):
    """Handle Add Source form submission."""
    source_type = SourceType(type)
    form_data = {
        "name": name,
        "type": type,
        "host": host,
        "port": port,
        "database_name": database_name,
        "username": username,
    }
    try:
        source, _ = await service.create_source(
            name=name.strip(),
            source_type=source_type,
            host=host.strip(),
            port=port,
            database_name=database_name.strip(),
            username=username.strip(),
            password=password,
            test_first=True,  # Test during creation
        )
        return RedirectResponse(
            url=f"/admin/sources/{source.id}",
            status_code=status.HTTP_303_SEE_OTHER,
        )
    except (SourceAlreadyExistsError, AltrStreamError) as e:
        return templates.TemplateResponse(
            request=request,
            name="source_add.html",
            context={
                "active_page": "add_source",
                "form_data": form_data,
                "error": str(e),
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )


@web_router.get("/admin/sources/{source_id}", response_class=HTMLResponse)
async def source_details(
    request: Request,
    source_id: str,
    source_service: SourceService = Depends(get_source_service),
    schema_service: SchemaService = Depends(get_schema_service),
):
    """View details for a specific data source."""
    try:
        source = await source_service.get_source(source_id)
        schema = await schema_service.get_latest_schema(source_id)
        return templates.TemplateResponse(
            request=request,
            name="source_detail.html",
            context={
                "source": source,
                "schema": schema,
                "active_page": "dashboard",
            },
        )
    except SourceNotFoundError:
        raise HTTPException(status_code=404, detail="Source not found")


@web_router.post("/admin/sources/{source_id}/test", response_class=HTMLResponse)
async def test_saved_source_htmx(
    request: Request,
    source_id: str,
    service: SourceService = Depends(get_source_service),
):
    """HTMX endpoint for testing an existing source from details page."""
    try:
        result = await service.test_source_connection(source_id)
        return templates.TemplateResponse(
            request=request,
            name="partials/test_result.html",
            context={
                "result": result,
            },
        )
    except SourceNotFoundError:
        raise HTTPException(status_code=404, detail="Source not found")


@web_router.post("/admin/sources/{source_id}/discover", response_class=HTMLResponse)
async def discover_schema_htmx(
    request: Request,
    source_id: str,
    schema_service: SchemaService = Depends(get_schema_service),
):
    """HTMX endpoint for discovering schema and refreshing the page."""
    try:
        schema = await schema_service.discover_and_save_schema(source_id)
        # Return success notification with reload trigger
        response = HTMLResponse(
            f"""
            <div class="alert alert-success" style="display: flex; justify-content: space-between; align-items: center;">
              <div>
                <strong>✓ Schema Discovered Successfully!</strong>
                <p>Found {schema.entity_count} tables/entities and {schema.total_field_count} total columns.</p>
              </div>
              <a href="/admin/sources/{source_id}/schema" class="btn btn-primary btn-sm">Open Schema Viewer &rarr;</a>
            </div>
            """
        )
        response.headers["HX-Refresh"] = "true"
        return response
    except Exception as e:
        return HTMLResponse(
            f"""
            <div class="alert alert-error">
              <strong>✗ Schema Discovery Failed</strong>
              <p>{str(e)}</p>
            </div>
            """,
            status_code=200,
        )


@web_router.get("/admin/sources/{source_id}/schema", response_class=HTMLResponse)
async def view_source_schema(
    request: Request,
    source_id: str,
    source_service: SourceService = Depends(get_source_service),
    schema_service: SchemaService = Depends(get_schema_service),
):
    """Schema viewer for an external data source."""
    try:
        source = await source_service.get_source(source_id)
        schema = await schema_service.get_latest_schema(source_id)
        return templates.TemplateResponse(
            request=request,
            name="schema_viewer.html",
            context={
                "source": source,
                "schema": schema,
                "active_page": "dashboard",
            },
        )
    except SourceNotFoundError:
        raise HTTPException(status_code=404, detail="Source not found")


@web_router.post("/admin/sources/{source_id}/delete")
async def delete_source_web(
    source_id: str,
    service: SourceService = Depends(get_source_service),
):
    """Delete a source and redirect to dashboard."""
    await service.delete_source(source_id)
    return RedirectResponse(url="/", status_code=status.HTTP_303_SEE_OTHER)
