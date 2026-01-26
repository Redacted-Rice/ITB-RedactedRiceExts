-- clear_coverage.lua
-- helper script to clear previous luacov coverage data before running tests
-- this seems to be the typical approach since busted or luacov dont seem to have built in options
-- to automatically clear previous coverage data

-- clear luacov stats file if it exists
local stats_file = "luacov.stats.out"
local file = io.open(stats_file, "r")
if file then
	file:close()
	os.remove(stats_file)
end

-- clear report file as well. Probably not necessary but ensures a new report
local report_file = "luacov.report.out"
local report_file_handle = io.open(report_file, "r")
if report_file_handle then
	report_file_handle:close()
	os.remove(report_file)
end