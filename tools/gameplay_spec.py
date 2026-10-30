"""The gameplay checks a release has to pass, in one place.

`verify_gameplay.py` runs this list and writes the result; `build_packages.py`
reads the same list back and refuses a record that is short of it. Keeping the
list here means a record cannot be made to pass by quietly dropping a check.
"""

REPLAY_CITIES = ('shenzhen', 'shanghai', 'beijing', 'guangzhou', 'chengdu')

# Checkpoints each city's full replay has produced. The check is `>=` so a
# longer run passes, while a truncated or partly-failed run does not.
CHECKPOINT_FLOOR = {
    'shenzhen': 110,
    'shanghai': 143,
    'beijing': 139,
    'guangzhou': 127,
    'chengdu': 114,
}

# Cross-process resume is the only evidence that a saved game can be picked up
# again; the in-process checkpoints do not prove it.
RESUME_BREAKPOINT = 15

GD_SCRIPTS = (
    ('gd.history_collection_checks', 'tests/history_collection_checks.gd'),
    ('gd.history_collection_flow', 'tests/history_collection_flow.gd'),
    ('gd.story_checks', 'tests/story_checks.gd'),
    ('gd.official_target_checks', 'tests/official_target_checks.gd'),
    ('gd.story_save_checks', 'tests/story_save_checks.gd'),
    ('gd.save_roundtrip_checks', 'tests/save_roundtrip_checks.gd'),
    ('gd.engineering_construction_checks', 'tests/engineering_construction_checks.gd'),
    ('gd.yizhuang_connector_checks', 'tests/yizhuang_connector_checks.gd'),
    ('gd.shenzhen13_opening_checks', 'tests/shenzhen13_opening_checks.gd'),
    ('gd.story_layout_checks', 'tests/story_layout_checks.gd'),
    ('gd.map_hit_checks', 'tests/map_hit_checks.gd'),
    ('gd.presentation_geometry_checks', 'tests/presentation_geometry_checks.gd'),
    ('gd.chapter_lookup_checks', 'tests/chapter_lookup_checks.gd'),
    ('gd.legacy_network_repair_checks', 'tests/legacy_network_repair_checks.gd'),
)

PY_CHECKS = (
    ('py.campaign_task_integrity', ['tools/test_campaign_task_integrity.py']),
    ('py.official_coverage_rules', ['tools/test_official_coverage_rules.py']),
    ('py.project_plans', ['tools/test_project_plans.py']),
    ('py.project_chapter_report', ['tools/report_project_chapters.py', '--check']),
)


def required_ids():
    """Every check id a release record has to contain, in a stable order."""
    ids = []
    for city in REPLAY_CITIES:
        ids.append(f'replay.fresh.{city}')
    for city in REPLAY_CITIES:
        ids.append(f'replay.resume.{city}')
    ids.extend(name for name, _ in GD_SCRIPTS)
    ids.extend(name for name, _ in PY_CHECKS)
    return ids
