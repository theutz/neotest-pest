local logger = require("neotest.logging")

local M = {}
local separator = "::"

---Generate an id which we can use to match Treesitter queries and Pest tests
---@param position neotest.Position The position to return an ID for
---@param namespace neotest.Position[] Any namespaces the position is within
---@return string
M.make_test_id = function(position)
    -- Treesitter starts line numbers from 0 so we add 1
    local id = position.path .. separator .. position.name

    logger.info("Path to test file:", { position.path })
    logger.info("Treesitter id:", { id })

    return id
end

---Recursively iterate through a deeply nested table to obtain specified keys
---@param data_table table
---@param key string
---@param output_table table
---@return table
local function iterate_key(data_table, key, output_table)
    if type(data_table) == "table" then
        for k, v in pairs(data_table) do
            if key == k then
                table.insert(output_table, v)
            end
            iterate_key(v, key, output_table)
        end
    end
    return output_table
end

---Extract the failure messages from the tests
---@param tests table,
---@return boolean,table,table
local function errors_or_fails(tests)
    local failed = false
    local errors = {}
    local fails = {}

    iterate_key(tests, "error", errors)
    iterate_key(tests, "failure", fails)

    if #errors > 0 or #fails > 0 then
        failed = true
    end

    return failed, errors, fails
end

local function make_short_output(test_attr, status)
    return string.upper(status) .. " | " .. test_attr.name
end

---Make the outputs for a given test
---@param test table
---@param output_file string
---@return table
local function make_outputs(test, output_file)
    logger.info("Pre-output test:", test)
    local test_attr = test["_attr"] or test[1]["_attr"]
    local name = string.gsub(test_attr.name, "it (.*)", "%1")

    local test_id = test_attr.file .. separator .. name
    logger.info("Pest id:", { test_id })

    local test_output = {
        status = "passed",
        short = make_short_output(test_attr, "passed"),
        output_file = output_file,
    }

    local test_failed, errors, fails = errors_or_fails(test)

    if test_failed then
        logger.info("test_failed:", { test_failed, errors, fails })
        test_output.status = "failed"

        if #errors > 0 then
            local message = errors[1][1]
            test_output.short = make_short_output(test_attr, "error") .. "\n\n" .. message
            test_output.errors = {
                {
                    message = message
                },
            }
        elseif #fails > 0 then
            local message = fails[1][1]
            test_output.short = make_short_output(test_attr, "failed") .. "\n\n" .. message
            test_output.errors = {
                {
                    message = message
                }
            }
        end
    end

    if test['skipped'] then
        test_output.status = "skipped"
        test_output.short = make_short_output(test_attr, "skipped")
    end

    logger.debug("test_output:", test_output)

    return test_id, test_output
end

---Iterate through test results and create a table of test IDs and outputs
---@param tests table
---@param output_file string
---@param output_table table
---@return table
local function iterate_test_outputs(tests, output_file, output_table)
    for i = 1, #tests, 1 do
        if #tests[i] == 0 then
            local test_id, test_output = make_outputs(tests[i], output_file)
            output_table[test_id] = test_output
        else
            iterate_test_outputs(tests[i], output_file, output_table)
        end
    end
    return output_table
end

---Get the test results from the parsed xml
---@param parsed_xml_output table
---@param output_file string
---@return neotest.Result[]
M.get_test_results = function(parsed_xml_output, output_file)
    local tests = iterate_key(parsed_xml_output, "testcase", {})
    return iterate_test_outputs(tests, output_file, {})
end

return M
