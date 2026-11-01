# lib_test_tz.sh - pin the timezone of a time-relative test suite (2026-11-01, package K4).
# The 2026-11-01 04:27 CST coverage run failed 10 lines in 4 suites (test_ovn_research_trigger_check, test_auto_research_lock, test_research_trigger_monotonic, test_box_recover):
# they synthesize "N hours ago" as LOCAL wall-clock strings (date +'%F %T', touch -t, strftime) and the code under test parses them back with mktime. On the night America/Chicago
# falls back (01:00-02:00 occurs twice) a wall-clock string in that hour is ambiguous, so "3h ago" came back as 2h or 3.5h. The suites measure elapsed time, not the zone, so they run
# in UTC (no DST, ever). SOURCE this from the suite; it never touches the caller's real environment outside the suite's own process.
export TZ=UTC
