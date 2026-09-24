"""Unit tests for SemVer 2.0.0 implementation and DirectUpgradeResolver."""

import pytest
from altr_stream.domain.semver import (
    DirectUpgradeResolver,
    ReleaseChannel,
    ReleaseInfo,
    SemVer,
)


class TestSemVerParsing:
    def test_parse_basic_versions(self):
        v = SemVer.parse("1.2.3")
        assert v.major == 1
        assert v.minor == 2
        assert v.patch == 3
        assert v.prerelease is None
        assert v.build is None
        assert str(v) == "1.2.3"

    def test_parse_with_v_prefix(self):
        v = SemVer.parse("v0.13.1-alpha")
        assert v.major == 0
        assert v.minor == 13
        assert v.patch == 1
        assert v.prerelease == "alpha"
        assert str(v) == "0.13.1-alpha"

    def test_parse_prerelease_and_build(self):
        v = SemVer.parse("1.0.0-beta.2+exp.sha.5114f85")
        assert v.major == 1
        assert v.minor == 0
        assert v.patch == 0
        assert v.prerelease == "beta.2"
        assert v.build == "exp.sha.5114f85"

    def test_parse_invalid_versions_raise_error(self):
        invalid = [
            "",
            "1",
            "1.2",
            "1.2.3.4",
            "01.2.3",  # Leading zero in major
            "1.02.3",  # Leading zero in minor
            "1.2.03",  # Leading zero in patch
            "random-string",
            None,
        ]
        for inv in invalid:
            with pytest.raises(ValueError):
                SemVer.parse(inv)
            assert SemVer.try_parse(inv) is None


class TestSemVerComparison:
    def test_major_minor_patch_precedence(self):
        assert SemVer.parse("0.13.1") < SemVer.parse("0.13.2")
        assert SemVer.parse("0.13.2") < SemVer.parse("0.14.0")
        assert SemVer.parse("0.14.0") < SemVer.parse("1.0.0")
        assert SemVer.parse("1.0.0") < SemVer.parse("2.0.0")

    def test_prerelease_vs_normal(self):
        # A normal version has greater precedence than a pre-release version
        assert SemVer.parse("1.0.0-alpha") < SemVer.parse("1.0.0")
        assert SemVer.parse("1.0.0-beta") < SemVer.parse("1.0.0")
        assert SemVer.parse("1.0.0-rc.1") < SemVer.parse("1.0.0")

    def test_roadmap_progression(self):
        # Specific project roadmap order:
        # 0.13.1-alpha < 0.13.2-alpha < 0.13.3-alpha < 1.0.0-beta < 1.0.0
        v1 = SemVer.parse("0.13.1-alpha")
        v2 = SemVer.parse("0.13.2-alpha")
        v3 = SemVer.parse("0.13.3-alpha")
        v4 = SemVer.parse("1.0.0-beta")
        v5 = SemVer.parse("1.0.0")

        assert v1 < v2 < v3 < v4 < v5
        assert v5 > v4 > v3 > v2 > v1

    def test_prerelease_lexical_and_numeric_sort(self):
        # Spec 11.4:
        # 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
        seq = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
        ]
        parsed = [SemVer.parse(s) for s in seq]
        for i in range(len(parsed) - 1):
            assert parsed[i] < parsed[i + 1]

    def test_build_metadata_ignored_in_precedence(self):
        v1 = SemVer.parse("1.0.0+build.1")
        v2 = SemVer.parse("1.0.0+build.2")
        assert v1 == v2
        assert not (v1 < v2)
        assert not (v1 > v2)


class TestReleaseChannel:
    def test_channel_derivation(self):
        assert SemVer.parse("0.13.1-alpha").channel == ReleaseChannel.ALPHA
        assert SemVer.parse("1.0.0-beta").channel == ReleaseChannel.BETA
        assert SemVer.parse("1.0.0-rc.1").channel == ReleaseChannel.BETA
        assert SemVer.parse("1.0.0").channel == ReleaseChannel.STABLE

    def test_channel_hierarchy_filtering(self):
        assert DirectUpgradeResolver.is_channel_allowed(ReleaseChannel.ALPHA, ReleaseChannel.ALPHA) is True
        assert DirectUpgradeResolver.is_channel_allowed(ReleaseChannel.BETA, ReleaseChannel.ALPHA) is True
        assert DirectUpgradeResolver.is_channel_allowed(ReleaseChannel.STABLE, ReleaseChannel.ALPHA) is True

        assert DirectUpgradeResolver.is_channel_allowed(ReleaseChannel.ALPHA, ReleaseChannel.BETA) is False
        assert DirectUpgradeResolver.is_channel_allowed(ReleaseChannel.BETA, ReleaseChannel.BETA) is True
        assert DirectUpgradeResolver.is_channel_allowed(ReleaseChannel.STABLE, ReleaseChannel.BETA) is True

        assert DirectUpgradeResolver.is_channel_allowed(ReleaseChannel.ALPHA, ReleaseChannel.STABLE) is False
        assert DirectUpgradeResolver.is_channel_allowed(ReleaseChannel.BETA, ReleaseChannel.STABLE) is False
        assert DirectUpgradeResolver.is_channel_allowed(ReleaseChannel.STABLE, ReleaseChannel.STABLE) is True


class TestDirectUpgradeResolver:
    def _create_release(self, tag: str) -> ReleaseInfo:
        v = SemVer.parse(tag)
        return ReleaseInfo(
            version=v,
            tag_name=tag,
            name=f"Release {tag}",
            published_at="2026-09-24T00:00:00Z",
            body="Release notes",
            prerelease=v.is_prerelease,
            html_url=f"https://github.com/helloaltr/altr-stream/releases/tag/{tag}",
        )

    def test_direct_upgrade_skips_intermediate_versions(self):
        # Current: 1.1.0; Available: 1.2.0, 1.5.0, 2.0.0 -> Selects 2.0.0 directly
        current = SemVer.parse("1.1.0")
        releases = [
            self._create_release("v1.2.0"),
            self._create_release("v1.5.0"),
            self._create_release("v2.0.0"),
        ]
        plan = DirectUpgradeResolver.resolve_direct_upgrade(current, releases, channel=ReleaseChannel.STABLE)
        assert plan.update_available is True
        assert plan.target_version == SemVer.parse("2.0.0")
        assert plan.target_release.tag_name == "v2.0.0"

    def test_direct_upgrade_alpha_to_beta_and_stable(self):
        # Current: 0.13.1-alpha; Available: 0.13.2-alpha, 1.0.0-beta, 1.0.0
        current = SemVer.parse("0.13.1-alpha")
        releases = [
            self._create_release("v0.13.2-alpha"),
            self._create_release("v1.0.0-beta"),
            self._create_release("v1.0.0"),
        ]
        # In alpha channel, highest available is 1.0.0
        plan = DirectUpgradeResolver.resolve_direct_upgrade(current, releases, channel=ReleaseChannel.ALPHA)
        assert plan.update_available is True
    def test_direct_upgrade_0_13_2_to_0_13_3_alpha(self):
        # Explicit milestone requirement: 0.13.2-alpha -> 0.13.3-alpha is a valid direct upgrade
        current = SemVer.parse("0.13.2-alpha")
        releases = [
            self._create_release("v0.13.1-alpha"),
            self._create_release("v0.13.2-alpha"),
            self._create_release("v0.13.3-alpha"),
        ]
        plan = DirectUpgradeResolver.resolve_direct_upgrade(
            current_version=current,
            available_releases=releases,
            channel=ReleaseChannel.ALPHA,
        )
        assert plan.update_available is True
        assert plan.target_version == SemVer.parse("0.13.3-alpha")
        assert plan.target_release is not None
        assert plan.target_release.tag_name == "v0.13.3-alpha"

    def test_channel_restriction_stable_ignores_prerelease(self):
        current = SemVer.parse("1.0.0")
        releases = [
            self._create_release("v1.1.0-alpha"),
            self._create_release("v1.1.0-beta"),
        ]
        plan = DirectUpgradeResolver.resolve_direct_upgrade(current, releases, channel=ReleaseChannel.STABLE)
        assert plan.update_available is False
        assert plan.target_version is None

    def test_already_latest_version(self):
        current = SemVer.parse("2.0.0")
        releases = [
            self._create_release("v1.0.0"),
            self._create_release("v1.5.0"),
            self._create_release("v2.0.0"),
        ]
        plan = DirectUpgradeResolver.resolve_direct_upgrade(current, releases)
        assert plan.update_available is False
        assert plan.target_version is None

    def test_empty_releases_list(self):
        current = SemVer.parse("1.0.0")
        plan = DirectUpgradeResolver.resolve_direct_upgrade(current, [])
        assert plan.update_available is False
        assert plan.target_version is None
        assert plan.all_releases == []

    def test_duplicate_releases_handled(self):
        current = SemVer.parse("1.0.0")
        releases = [
            self._create_release("v1.1.0"),
            self._create_release("1.1.0"),  # Duplicate with/without v
        ]
        plan = DirectUpgradeResolver.resolve_direct_upgrade(current, releases)
        assert plan.update_available is True
        assert plan.target_version == SemVer.parse("1.1.0")
        assert len(plan.all_releases) == 1
