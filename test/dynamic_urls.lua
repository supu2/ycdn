-- Define the range for the dynamic URLs
min = 100
max = 500  -- Adjust this based on the number of URLs you want to generate

-- Seed the random number generator
math.randomseed(os.time())

-- Define the request function
request = function()
    -- Generate a random URL in the specified range
    local width = math.random(min, max)
    local height = math.random(min, max)
    local path = "/resize/" .. width .. "/".. height .. "/aHR0cHM6Ly9jZG4uZHNtY2RuLmNvbS90eTk1L3Byb2R1Y3QvbWVkaWEvaW1hZ2VzLzIwMjEwNDA0LzE1LzRkYTFiMTRiLzEzNjIzODAzLzEvMV9vcmdfem9vbS5qcGc"
    return wrk.format("GET", path)
end