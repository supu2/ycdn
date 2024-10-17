-- Define the range for the dynamic URLs
min = 100
max = 200  -- Adjust this based on the number of URLs you want to generate

-- Seed the random number generator
math.randomseed(os.time())

-- Define the request function
request = function()
    -- Generate a random URL in the specified range
    local width = math.random(min, max)
    local height = math.random(min, max)
    local path = "/resize/" .. width .. "/".. height .. "/aHR0cDovLzE5Mi4xNjguMTIyLjE6ODAwMC8udG1wLzhLLmpwZWc"
    return wrk.format("GET", path)
end