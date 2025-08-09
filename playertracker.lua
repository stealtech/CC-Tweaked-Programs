-- ============================================================================
 
-- Configuration
 
-- ============================================================================
 
local CONFIG = {
 
    -- AFK Detection Settings
 
    AFK_THRESHOLD = 15,         -- Updates (~60s assuming ~4s update cycle) before marked AFK if stationary.
 
                                -- A lower value means faster AFK detection, a higher value reduces false positives.
 
    POSITION_THRESHOLD = 0.1,   -- Max movement distance (per axis, per tick) to be considered stationary.
 
                                -- Tune this based on potential minor player movements (e.g., in water).
 
    PITCH_YAW_THRESHOLD = 0.05, -- Max pitch/yaw change per tick to be considered stationary.
 
                                -- Tune this based on subtle aim changes.
 
    PATTERN_THRESHOLD = 5,      -- Minimum number of repeating movement vector patterns needed for AFK pool detection. (Slightly reduced from original)
 
                                -- Lower value detects patterns with fewer repetitions.
 
    HISTORY_SIZE = 25,          -- Number of past positions stored per player for pattern detection. (Increased from original)
 
                                -- Larger history allows detection of longer or more complex patterns.
 
    PATTERN_LOOKBACK = 6,      -- How many previous movements to check for patterns (max). Should be <= HISTORY_SIZE - 2. (Increased from original)
 
                                -- Defines the window size for pattern comparison. A larger window can find longer repeating sequences.
 
    PATTERN_MIN_HISTORY = 8,   -- Minimum history entries needed before pattern detection starts. Should be <= HISTORY_SIZE. (Increased from original)
 
                                -- Prevents pattern detection on insufficient data points, ensuring valid comparisons.
 
    PATTERN_DIFF_THRESHOLD = 0.01, -- Max difference allowed between movement vectors to be considered the same pattern. (Increased slightly from original)
 
                                 -- Tolerance for floating-point inaccuracies or minor inconsistencies in automated movement.
 
 
 
    -- Display & Monitor Settings
 
    STATS_INTERVAL = 300,       -- Seconds between statistics prints to console (5 minutes).
 
    DIMENSION_CHANGE_DISPLAY_CYCLES = 6, -- Update cycles before clearing displayed dimension changes (~30-40s assuming ~5-7s cycle).
 
                                         -- Changed from 3 to 6 (approx 5-6 refreshes)
 
    MONITOR_SCALE = 0.5,        -- Text size on monitor. -- NOTE: This is overridden if dynamic scaling is enabled
 
                                -- Adjust for desired text size. Lower values make text smaller, fitting more data.
 
    INDICATOR_DELAY_SECONDS = 0, -- How long to show the update indicator per player (seconds). 0 = brief flash, >0 = potential slowdown.
 
                                 -- Setting this > 0 will pause rendering for each player's row, affecting performance.
 
    DETECTOR_POS = { x = -17020, y = 36, z = -29233 }, -- Coordinates of the Player Detector block.
 
                                                      -- Used to calculate distance to players.
 
 
 
    -- Health Configuration
 
    DEFAULT_MAX_HEALTH = 20,    -- Assumed max health if not provided by API (e.g., vanilla players).
 
    MAX_POSSIBLE_HEALTH = 5000, -- Maximum possible health on the server (used for health bar scaling/coloring).
 
                                -- Adjust this to match the highest possible health value on your server (e.g., from mods).
 
 
 
    -- Position Pool (Optimization - may not be necessary, micro-optimization)
 
    POSITION_POOL_ENABLED = true, -- Enable/disable the position object pool. May reduce garbage collection pauses.
 
    POSITION_POOL_MAX_SIZE = 500 -- Max number of unused position objects to keep in the pool.
 
}
 
 
 
-- ============================================================================
 
-- Health Color Ranges (Define once for efficiency - omitted for brevity)
 
-- ============================================================================
 
-- Defines colors based on health points thresholds. Ordered from highest HP threshold to lowest.
 
-- The first range matched (from top to bottom) determines the color.
 
local HEALTH_COLOR_RANGES = {
 
    { value = 5000, color = colors.purple },  -- 5000+ HP (e.g., Max HP on server)
 
    { value = 4000, color = colors.blue },    -- 4000-4999 HP
 
    { value = 3000, color = colors.green },   -- 3000-3999 HP
 
    { value = 2000, color = colors.lime },    -- 2000-2999 HP
 
    { value = 1000, color = colors.yellow },  -- 1000-1999 HP
 
    { value = 500,  color = colors.orange },  -- 500-999 HP
 
    { value = 100,  color = colors.red },     -- 100-499 HP
 
    { value = 0,    color = colors.gray }     -- 0-99 HP (or dead/invalid health data)
 
}
 
 
 
 
 
-- ============================================================================
 
-- Initialization (omitted for brevity, remains the same as previous version)
 
-- ============================================================================
 
 
 
--- Initializes and returns required peripherals (Player Detector, Monitor).
 
-- Ensures peripherals are attached and sets initial monitor state.
 
-- @return The radar peripheral object.
 
-- @return The monitor peripheral object.
 
local function initPeripherals()
 
    -- Attempt to find the required peripherals by type.
 
    local radar = peripheral.find("playerDetector")
 
    local monitor = peripheral.find("monitor")
 
 
 
    -- Use assert to stop script execution with a clear error if peripherals are missing.
 
    -- This prevents runtime errors later if these essential peripherals are not found.
 
    assert(radar, "Error: No Player Detector found. Please attach one.")
 
    assert(monitor, "Error: No Monitor found. Please attach one.")
 
 
 
    -- Configure initial monitor text scale and clear it.
 
    monitor.setTextScale(CONFIG.MONITOR_SCALE)
 
    monitor.setBackgroundColour(colors.black) -- Ensure background is black
 
    monitor.clear() -- Clear any previous content on the monitor
 
 
 
    -- Return the found peripheral objects.
 
    return radar, monitor
 
end
 
 
 
-- Initialize peripherals and get their handles.
 
local Radar, Monitor = initPeripherals()
 
 
 
-- Recalculate monitor size *after* setting text scale.
 
local MonitorWidth, MonitorHeight = Monitor.getSize()
 
print(string.format("Initialized Monitor Size: %d x %d at scale %.1f", MonitorWidth, MonitorHeight, Monitor.getTextScale())) -- Log final size
 
 
 
 
 
-- ============================================================================
 
-- Data Structures & State (omitted for brevity, remains the same as previous version)
 
-- ============================================================================
 
 
 
--- Object pool for position tables to potentially reduce garbage collection pauses.
 
-- Reuses tables instead of creating new ones repeatedly.
 
local PositionPool = {
 
    items = {}, -- List of reusable tables
 
    --- Acquires a table from the pool or creates a new one if the pool is empty.
 
    -- @return An empty table, potentially reused from the pool.
 
    acquire = function(self)
 
        -- If pool is disabled, just return a new table.
 
        if not CONFIG.POSITION_POOL_ENABLED then return {} end
 
        -- Try to remove an item from the end of the pool table.
 
        -- If the pool is empty, table.remove will return nil, and a new table {} is created.
 
        return table.remove(self.items) or {}
 
    end,
 
    --- Releases a table back into the pool if space is available.
 
    -- Clears the table before adding it back to ensure no stale data is kept.
 
    -- @param item The table to release (assumes it's a position table {x,y,z}).
 
    release = function(self, item)
 
        -- If pool is disabled, do nothing (table will be garbage collected naturally).
 
        if not CONFIG.POSITION_POOL_ENABLED then return end
 
        -- Clear table contents to prepare for reuse.
 
        for k in pairs(item) do item[k] = nil end
 
        -- Add the cleared table back to the pool if it's not full.
 
        if #self.items < CONFIG.POSITION_POOL_MAX_SIZE then
 
            table.insert(self.items, item)
 
        end
 
        -- If the pool is full, the table will be garbage collected naturally.
 
    end
 
}
 
 
 
-- Stores per-player movement data and AFK state for detection.
 
-- Key: username (string)
 
-- Value: table {
 
--   LastPitch (number), LastYaw (number),
 
--   LastPos ({x,y,z} table),
 
--   UnchangedTicks (number, how many ticks stationary/pattern detected),
 
--   PosHistory ({ {x,y,z}, ...} table, recent positions for pattern detection)
 
-- }
 
local PlayerMovement = {}
 
 
 
-- Stores runtime statistics about the script's operation.
 
local Statistics = {
 
    TotalPlayers = 0,       -- Number of players found in the last radar scan.
 
    AfkPlayers = 0,         -- Number of players marked as AFK in the last scan.
 
    DimensionChanges = 0,   -- Total count of dimension changes detected since script start.
 
    StartTime = 0,          -- os.time() when the script started (used for uptime).
 
    LastPrintTime = 0   -- os.time() when statistics were last printed to console.
 
}
 
 
 
-- Stores recent dimension changes detected via 'playerChangedDimension' events.
 
-- Used for displaying recent changes on the monitor.
 
-- Key: username (string)
 
-- Value: table { {FromDimension (string), ToDimension (string), TimeStamp (number)}, ... }
 
local DimensionChanges = {}
 
-- NOTE: Consider adding a per-player limit to this table if needed to prevent unbounded growth.
 
 
 
-- Cycle counter used to periodically clear the displayed DimensionChanges table.
 
local DimensionClearCycle = 0
 
 
 
 
 
-- ============================================================================
 
-- Column Definition & Caching (omitted for brevity)
 
-- ============================================================================
 
 
 
-- Defines the columns to display on the monitor.
 
-- Note: Leading/trailing spaces in Name are removed; padding is handled by FormatColumn.
 
local Columns = {
 
    { Name = "Name",       Width = 18, Align = "left",  Color = colors.yellow,  Key = "username", Padding = 1 },
 
    { Name = "AFK",        Width = 10, Align = "left",  Color = colors.gray,    Key = "afk", Padding = 1 },
 
    { Name = "Dist",       Width = 10, Align = "left",  Color = colors.cyan,    Key = "distance", Padding = 1 },
 
    { Name = "Position",   Width = 20, Align = "left",  Color = colors.lime,    Key = "position", Padding = 1 },
 
    { Name = "Health",     Width = 11, Align = "left",  Color = colors.red,     Key = "health", Padding = 1 },
 
    { Name = "Dimension",  Width = 16, Align = "left",  Color = colors.purple,  Key = "dimension", Padding = 1 },
 
    { Name = "Respawn",    Width = 21, Align = "left",  Color = colors.orange,  Key = "respawn", Padding = 1 },
 
    { Name = "R.Dim",      Width = 13, Align = "left",  Color = colors.blue,    Key = "respawnDim", Padding = 1 },
 
    { Name = "Pitch",      Width = 7,  Align = "left",  Color = colors.magenta, Key = "pitch", Padding = 1 },
 
    { Name = "Yaw",        Width = 7,  Align = "left",  Color = colors.pink,    Key = "yaw", Padding = 1 }
 
}
 
 
 
--- Pre-calculates formatting strings, validates column widths, and calculates total display width.
 
-- @param columns The table defining columns (like `Columns` above).
 
-- @return A cache table with processed column data and format strings.
 
-- @return The total calculated width of all columns including padding.
 
local function calculateColumnCache(columns, monitorWidth)
 
    local cache = {}
 
    local totalWidth = 0
 
 
 
    for i, col in ipairs(columns) do
 
        -- Ensure width is at least 1.
 
        local width = math.max(1, col.Width or 1)
 
        -- Default alignment to left.
 
        local align = col.Align or "left"
 
        -- Padding defaults to 0 if not specified.
 
        local padding = math.max(0, col.Padding or 0) -- Default padding of 0 spaces
 
 
 
        -- Determine printf format based on alignment.
 
        -- '%s' is for string. '-' indicates left alignment.
 
        local format = align == "right" and "%%%ds" or "%%-%ds"
 
 
 
        cache[i] = {
 
            Name = (col.Name or ""):match("^%s*(.-)%s*$"), -- Trim leading/trailing whitespace from name
 
            Width = width,
 
            Align = align,
 
            Color = col.Color or colors.white, -- Default color to white
 
            Format = string.format(format, width), -- Pre-calculated format string
 
            Key = col.Key,
 
            Padding = padding
 
        }
 
 
 
        -- Accumulate total width including column width and its padding.
 
        totalWidth = totalWidth + width + padding
 
    end
 
 
 
    -- Warn if the total calculated width exceeds the monitor width.
 
    -- This helps the user understand why content might be clipped.
 
    if totalWidth > monitorWidth then
 
        print(string.format("Warning: Calculated Column Width (%d) Exceeds Monitor Width (%d)", totalWidth, monitorWidth))
 
        print("Some content may be clipped or wrap unexpectedly.")
 
    end
 
 
 
    -- Return both the cache and the total calculated width.
 
    return cache, totalWidth
 
end
 
 
 
-- Generate the cache and get the total width from the column definitions, using the determined monitor width.
 
local ColumnCache, TotalCalculatedWidth = calculateColumnCache(Columns, MonitorWidth)
 
 
 
 
 
-- ============================================================================
 
-- AFK Detection Logic
 
-- ============================================================================
 
 
 
--- Detects if recent movement history shows a repetitive pattern (e.g., typical AFK pool movement from fans/belts).
 
-- Compares the latest movement vector against previous ones in the history.
 
-- This helps identify automated or forced movement that is not player-initiated.
 
-- @param posHistory A table of recent position tables ({x,y,z}).
 
-- @param username The username (for debug printing).
 
-- @return true if a repetitive pattern (meeting threshold) is detected, false otherwise.
 
local function detectMovementPattern(posHistory, username) -- Added username parameter for debugging
 
 
 
    -- Need enough history points to calculate movement vectors and look back.
 
    if #posHistory < CONFIG.PATTERN_MIN_HISTORY then
 
        -- print(string.format("DEBUG: %s: History size %d is less than PATTERN_MIN_HISTORY %d", username, #posHistory, CONFIG.PATTERN_MIN_HISTORY)) -- DEBUG
 
        return false
 
    end
 
 
 
    local patternCount = 0
 
    -- Get the last two positions to calculate the latest movement vector.
 
    local lastPos = posHistory[#posHistory]
 
    local prevPos = posHistory[#posHistory - 1]
 
 
 
    -- Should not happen if #posHistory check passes and HISTORY_SIZE is sufficient, but safeguard.
 
    if not lastPos or not prevPos then
 
         -- print(string.format("DEBUG: %s: Last or prev pos missing in history", username)) -- DEBUG
 
         return false
 
    end
 
 
 
    -- Calculate the latest movement vector components (change in position per tick).
 
    local lastDiffX = lastPos.x - prevPos.x
 
    local lastDiffY = lastPos.y - prevPos.y
 
    local lastDiffZ = lastPos.z - prevPos.z
 
 
 
    -- print(string.format("DEBUG: %s: Latest movement vector: %.4f, %.4f, %.4f", username, lastDiffX, lastDiffY, lastDiffZ)) -- DEBUG
 
 
 
    -- Define the range of history entries to check for repeating patterns.
 
    -- Start from the third-to-last entry and go back up to PATTERN_LOOKBACK entries.
 
    -- The range is from index `startIndex` down to `endIndex`.
 
    local startIndex = #posHistory - 2 -- Index of the second-to-last position in the history (the 'from' point of the second-to-last vector)
 
    local endIndex = math.max(1, #posHistory - CONFIG.PATTERN_LOOKBACK - 1) -- Index of the earliest position to consider (the 'from' point of the oldest vector to check)
 
 
 
    -- Ensure the start index is not less than the end index.
 
    if startIndex < endIndex then
 
        -- print(string.format("DEBUG: %s: Start index %d < End index %d, skipping pattern check", username, startIndex, endIndex)) -- DEBUG
 
        return false -- Safety check, should be handled by PATTERN_MIN_HISTORY and PATTERN_LOOKBACK config
 
    end
 
 
 
 
 
    -- Loop backwards through the relevant history segment to compare past movements to the latest movement.
 
    for i = startIndex, endIndex, -1 do
 
        local currentPos = posHistory[i + 1] -- The 'to' position for this historical movement vector
 
        local previousPos = posHistory[i]     -- The 'from' position for this historical movement vector
 
 
 
        -- Should not happen if loop indices are correct and history exists, but safeguard anyway.
 
        if not currentPos or not previousPos then break end
 
 
 
        -- Calculate the historical movement vector components.
 
        local diffX = currentPos.x - previousPos.x
 
        local diffY = currentPos.y - previousPos.y
 
        local diffZ = currentPos.z - previousPos.z
 
 
 
        -- print(string.format("DEBUG: %s: Comparing to vector at index %d: %.4f, %.4f, %.4f", username, i, diffX, diffY, diffZ)) -- DEBUG
 
 
 
        -- Check if the historical vector is very close to the latest vector.
 
        -- Use the configured PATTERN_DIFF_THRESHOLD to allow for minor variations common in automated movement.
 
        if math.abs(diffX - lastDiffX) <= CONFIG.PATTERN_DIFF_THRESHOLD and
 
           math.abs(diffY - lastDiffY) <= CONFIG.PATTERN_DIFF_THRESHOLD and
 
           math.abs(diffZ - lastDiffZ) <= CONFIG.PATTERN_DIFF_THRESHOLD then
 
            patternCount = patternCount + 1 -- Increment count if a matching pattern is found.
 
            -- print(string.format("DEBUG: %s: Pattern match found at index %d! patternCount = %d", username, i, patternCount)) -- DEBUG
 
        end
 
    end
 
 
 
    -- If the number of found similar vectors meets or exceeds the configured threshold, a pattern is detected.
 
    local patternDetected = patternCount >= CONFIG.PATTERN_THRESHOLD
 
    -- print(string.format("DEBUG: %s: Final pattern count %d. Threshold %d. Detected: %s", username, patternCount, CONFIG.PATTERN_THRESHOLD, tostring(patternDetected))) -- DEBUG
 
 
 
    return patternDetected
 
end
 
 
 
--- Updates a player's position history, maintaining a fixed size using the PositionPool.
 
-- Removes the oldest position if history size exceeds CONFIG.HISTORY_SIZE and adds the new one.
 
-- Using a fixed-size history and recycling position tables via the pool helps manage memory.
 
-- @param history The player's PosHistory table (passed by reference).
 
-- @param pos The player's current position table ({x,y,z}).
 
local function updatePositionHistory(history, pos)
 
    -- Check if the history size has reached the configured limit.
 
    while #history >= CONFIG.HISTORY_SIZE do
 
        -- Remove the oldest entry from the beginning of the history table.
 
        local oldPos = table.remove(history, 1)
 
        -- Release the table object back to the pool for potential reuse.
 
        PositionPool:release(oldPos)
 
    end
 
    -- Acquire a new position table from the pool or create one.
 
    local newPos = PositionPool:acquire()
 
    -- Copy the current position data into the acquired table. Handle potential nil values safely.
 
    newPos.x = pos.x or 0
 
    newPos.y = pos.y or 0
 
    newPos.z = pos.z or 0
 
    -- Add the current position table to the end of the history.
 
    table.insert(history, newPos)
 
end
 
 
 
 
 
--- Determines if a player is considered AFK based on lack of movement/rotation
 
-- over time OR detection of a repetitive movement pattern (e.g., AFK pool from fans/belts).
 
-- This function is called for each online player during each scan cycle.
 
-- @param username The player's username string.
 
-- @param plrPos The player's current position data table from the radar (includes pitch/yaw).
 
-- @return true if the player is considered AFK, false otherwise.
 
local function isPlayerAFK(username, plrPos)
 
    -- Retrieve the player's stored movement state, or initialize it if this is the first time seeing the player.
 
    local movement = PlayerMovement[username]
 
 
 
    -- Initialize state for a player seen for the first time in this scan or since script start.
 
    if not movement then
 
        movement = {
 
            LastPitch = plrPos.pitch or 0, -- Store current pitch, default to 0 if nil radar data
 
            LastYaw = plrPos.yaw or 0,     -- Store current yaw, default to 0 if nil radar data
 
            -- Acquire a position table from the pool for the last position storage.
 
            LastPos = PositionPool:acquire(),
 
            UnchangedTicks = 0, -- Start with 0 ticks where movement/pattern criterion is met
 
            PosHistory = {}     -- Initialize position history as an empty table
 
        }
 
        -- Store the initial position in the LastPos table. Handle nil safely.
 
        movement.LastPos.x = plrPos.x or 0
 
        movement.LastPos.y = plrPos.y or 0
 
        movement.LastPos.z = plrPos.z or 0
 
 
 
        PlayerMovement[username] = movement -- Store the new movement state table
 
        -- Add the initial position to the history.
 
        updatePositionHistory(movement.PosHistory, plrPos)
 
        -- print(string.format("DEBUG: %s: Initialized movement state.", username)) -- DEBUG
 
        return false -- A player cannot be AFK on the very first tick they are observed.
 
    end
 
 
 
    -- Calculate absolute differences from the last known state for position and rotation.
 
    -- Use 'or 0' for safety with potentially nil radar data points, preventing errors.
 
    local currentPitch = plrPos.pitch or 0
 
    local currentYaw = plrPos.yaw or 0
 
    local currentPosX = plrPos.x or 0
 
    local currentPosY = plrPos.y or 0
 
    local currentPosZ = plrPos.z or 0
 
 
 
    local pitchDiff = math.abs(movement.LastPitch - currentPitch)
 
    local yawDiff = math.abs(movement.LastYaw - currentYaw)
 
    local posDiffX = math.abs(movement.LastPos.x - currentPosX)
 
    local posDiffY = math.abs(movement.LastPos.y - currentPosY)
 
    local posDiffZ = math.abs(movement.LastPos.z - currentPosZ)
 
 
 
    -- print(string.format("DEBUG: %s: Pos: %.4f, %.4f, %.4f | Pitch: %.2f | Yaw: %.2f", username, currentPosX, currentPosY, currentPosZ, currentPitch, currentYaw)) -- DEBUG
 
    -- print(string.format("DEBUG: %s: PosDiff: %.4f, %.4f, %.4f | PitchDiff: %.2f | YawDiff: %.2f", username, posDiffX, posDiffY, posDiffZ, pitchDiff, yawDiff)) -- DEBUG
 
 
 
    -- Update history *before* checking patterns. This ensures the current position
 
    -- is part of the history used for pattern detection in THIS tick.
 
    updatePositionHistory(movement.PosHistory, plrPos)
 
 
 
    -- Check for a repetitive movement pattern using the updated history.
 
    local inAFKPool = detectMovementPattern(movement.PosHistory, username) -- Pass username for debug printing inside
 
 
 
    -- Check if the player is considered "stationary" based on minimal position and rotation changes
 
    -- being below the configured thresholds.
 
    local isStationary = pitchDiff <= CONFIG.PITCH_YAW_THRESHOLD and
 
                         yawDiff <= CONFIG.PITCH_YAW_THRESHOLD and
 
                         posDiffX <= CONFIG.POSITION_THRESHOLD and
 
                         posDiffY <= CONFIG.POSITION_THRESHOLD and
 
                         posDiffZ <= CONFIG.POSITION_THRESHOLD
 
 
 
    -- Player is considered potentially AFK for this tick if they are either stationary
 
    -- (not moving/rotating much) OR if their recent history shows a repetitive pattern
 
    -- characteristic of AFK pools.
 
    local isConsideredAFKThisTick = isStationary or inAFKPool
 
 
 
    if isConsideredAFKThisTick then
 
        -- If considered AFK this tick, increment the counter of consecutive ticks
 
        -- where the AFK criterion is met.
 
        movement.UnchangedTicks = movement.UnchangedTicks + 1
 
        -- print(string.format("DEBUG: %s: Considered AFK this tick. UnchangedTicks: %d", username, movement.UnchangedTicks)) -- DEBUG
 
    else
 
        -- If there was significant player-initiated movement or rotation,
 
        -- reset the unchanged ticks counter. This means the player is actively moving.
 
        -- print(string.format("DEBUG: %s: Not considered AFK this tick. Resetting UnchangedTicks.", username)) -- DEBUG
 
        movement.UnchangedTicks = 0
 
        -- When a player moves actively, their patterned movement (if any) is broken.
 
        -- We keep the history, but the AFK pool detection will fail if the pattern is broken.
 
    end
 
 
 
    -- Update the stored state (last position, pitch, yaw) using the current player data
 
    -- for the next time this function is called for this player.
 
    movement.LastPitch = currentPitch
 
    movement.LastYaw = currentYaw
 
    movement.LastPos.x = currentPosX
 
    movement.LastPos.y = currentPosY
 
    movement.LastPos.z = currentPosZ
 
 
 
    -- A player is marked as fully AFK for display purposes if they have met the
 
    -- stationary/pattern criterion for at least CONFIG.AFK_THRESHOLD consecutive ticks,
 
    -- OR if a repetitive pattern indicative of an AFK pool is detected. Pattern detection
 
    -- can flag a player as AFK even if the AFK_THRESHOLD for stationary ticks hasn't been met,
 
    -- as long as the history is sufficient and the pattern is clear.
 
    local finalAFKStatus = movement.UnchangedTicks >= CONFIG.AFK_THRESHOLD or inAFKPool
 
    -- if finalAFKStatus then print(string.format("DEBUG: %s: FINAL AFK STATUS: TRUE (Ticks: %d, Pattern: %s)", username, movement.UnchangedTicks, tostring(inAFKPool))) end -- DEBUG
 
    return finalAFKStatus
 
end
 
 
 
 
 
-- ============================================================================
 
-- Formatting Helpers (omitted for brevity)
 
-- ============================================================================
 
 
 
--- Formats text to fit a specific column width, handling alignment and padding.
 
-- @param text The text content to format (will be converted to string). Can be nil.
 
-- @param columnIndex The 1-based index of the column in ColumnCache.
 
-- @return Formatted string ready for printing, including trailing padding.
 
local function FormatColumn(text, columnIndex)
 
    -- Get the column definition from the cache using the index.
 
    local col = ColumnCache[columnIndex]
 
    -- Return an empty string if the column index is invalid (safety check).
 
    if not col then return "" end
 
 
 
    -- Convert the input text to a string, defaulting to an empty string if nil.
 
    local str = tostring(text or "")
 
    local targetWidth = col.Width
 
    -- Create the padding string based on the column's defined padding.
 
    local paddingStr = string.rep(" ", col.Padding)
 
 
 
    -- Truncate the string if it's longer than the target width.
 
    if #str > targetWidth then
 
        str = str:sub(1, targetWidth)
 
    -- Use the pre-calculated format string for alignment and width if the string is shorter.
 
    -- The format string handles adding spaces for alignment and padding to the target width.
 
    elseif #str < targetWidth then
 
         str = string.format(col.Format, str)
 
    end
 
    -- If #str == targetWidth, no adjustment is needed by the format string itself,
 
    -- but we still need to append the padding.
 
 
 
    -- Append the calculated padding string after the formatted text.
 
    return str .. paddingStr
 
end
 
 
 
--- Formats X, Y, Z coordinates into a fixed-width inline string.
 
-- Uses printf-like formatting to ensure consistent spacing and width.
 
-- @param x Coordinate value (number or nil).
 
-- @param y Coordinate value (number or nil).
 
-- @param z Coordinate value (number or nil).
 
-- @return Formatted coordinate string (e.g., "  1234 100  -567"). Defaults to "     0   0      0" if coordinates are nil.
 
local function FormatCoordinatesInline(x, y, z)
 
    -- Use string.format with specific width specifiers:
 
    -- %6d: Decimal integer, padded with spaces to a width of 6. Allows space for a sign and up to 5 digits.
 
    -- %3d: Decimal integer, padded with spaces to a width of 3. Suitable for Y coordinate (0-255 range typically).
 
    -- Default nil values to 0 for formatting.
 
    return string.format("%6d %3d %6d", x or 0, y or 0, z or 0)
 
end
 
 
 
--- Extracts and formats a dimension name from a namespaced string.
 
-- Converts a format like "minecraft:overworld" to "Overworld".
 
-- @param dimension The full dimension string (e.g., "minecraft:overworld") or nil.
 
-- @return Formatted dimension name (e.g., "Overworld"), or "?" if nil/invalid input.
 
local function FormatDimensionName(dimension)
 
    -- Check if the input is a non-empty string.
 
    if not dimension or type(dimension) ~= "string" or #dimension == 0 then return "?" end
 
    -- Use string.match to find the part after the last colon, or the whole string if no colon exists.
 
    local name = dimension:match("([^:]+)$") or dimension
 
    -- Capitalize the first letter of the extracted name.
 
    return name:gsub("^%l", string.upper)
 
end
 
 
 
--- Gets the appropriate color constant based on the player's current and maximum health.
 
-- Iterates through the defined `HEALTH_COLOR_RANGES`.
 
-- @param currentHealth The player's current health (number or nil).
 
-- @param maxHealth The player's maximum health (number or nil).
 
-- @return The color constant (e.g., colors.red) for the health display. Defaults to colors.gray.
 
local function GetHealthColor(currentHealth, maxHealth)
 
    -- Use default values if current or max health are nil.
 
    local ch = currentHealth or 0
 
    local mh = maxHealth or CONFIG.DEFAULT_MAX_HEALTH
 
 
 
    -- Handle edge case where max health is zero or negative to avoid division by zero or incorrect scaling.
 
    if mh <= 0 then
 
        return colors.gray -- Indicate invalid/unknown state
 
    end
 
 
 
    -- Iterate through the predefined ranges. The HEALTH_COLOR_RANGES table
 
    -- should be ordered from highest health value to lowest.
 
    for _, range in ipairs(HEALTH_COLOR_RANGES) do
 
        -- Check if the current health is greater than or equal to the range's value threshold.
 
        if ch >= range.value then
 
            return range.color -- Return the color for the first matching range found.
 
        end
 
    end
 
    -- This line should theoretically not be reached if a {value=0} entry exists in HEALTH_COLOR_RANGES,
 
    -- but it serves as a final fallback.
 
    return colors.gray
 
end
 
 
 
 
 
-- ============================================================================
 
-- Statistics & Event Handling (omitted for brevity)
 
-- ============================================================================
 
 
 
--- Prints runtime statistics to the console if the configured interval has passed.
 
-- Uses os.time() for time tracking.
 
local function PrintStatistics()
 
    -- Get the current time in seconds since the epoch.
 
    local currentTime = os.time()
 
 
 
    -- Check if the time elapsed since the last print is greater than or equal to the configured interval.
 
    if currentTime - Statistics.LastPrintTime >= CONFIG.STATS_INTERVAL then
 
        -- Calculate the total runtime in seconds and then minutes.
 
        local runtimeSeconds = currentTime - Statistics.StartTime
 
        local runtimeMinutes = math.floor(runtimeSeconds / 60)
 
 
 
        -- Print a clear header for the statistics output.
 
        print("\n=== Player Monitor Statistics ===") -- Add newline for separation
 
        -- Format and print the statistics.
 
        print(string.format("Runtime: %d minutes", runtimeMinutes))
 
        print(string.format("Total Players Tracked (Last Scan): %d", Statistics.TotalPlayers))
 
        print(string.format("Currently AFK Players (Last Scan): %d", Statistics.AfkPlayers))
 
        print(string.format("Detected Dimension Changes: %d", Statistics.DimensionChanges)) -- Total changes since start
 
        print("================================")
 
 
 
        -- Update the time the statistics were last printed.
 
        Statistics.LastPrintTime = currentTime
 
    end
 
end
 
 
 
--- Listens for 'playerChangedDimension' events in parallel and updates statistics/history.
 
-- Runs in a separate coroutine or thread via parallel.waitForAny.
 
local function ListenForDimensionChanges()
 
    -- Loop indefinitely to continuously listen for events.
 
    while true do
 
        -- Wait for any event. os.pullEvent suspends this coroutine until an event occurs.
 
        -- We are specifically interested in "playerChangedDimension".
 
        local event, username, fromDim, toDim = os.pullEvent("playerChangedDimension")
 
 
 
        -- Check if the received event is the target event and if the dimension actually changed.
 
        if event == "playerChangedDimension" and username and fromDim ~= toDim then
 
            -- Format dimension names for logging and display.
 
            local fromName = FormatDimensionName(fromDim)
 
            local toName = FormatDimensionName(toDim)
 
            -- Log the dimension change to the console.
 
            print(string.format("Dimension Change Detected: %s: %s -> %s", username, fromName, toName))
 
 
 
            -- Increment the global counter for total dimension changes.
 
            Statistics.DimensionChanges = Statistics.DimensionChanges + 1
 
 
 
            -- Store the change information per player in the DimensionChanges table.
 
            -- Initialize the player's entry as an empty table if it doesn't exist.
 
            DimensionChanges[username] = DimensionChanges[username] or {}
 
            -- Insert the new change event details at the end of the player's history.
 
            table.insert(DimensionChanges[username], {
 
                FromDimension = fromDim,
 
                ToDimension = toDim,
 
                TimeStamp = os.time() -- Record the time the event was processed.
 
            })
 
            -- Optional: Add logic here to limit the number of stored changes per player
 
            -- to prevent the DimensionChanges table from growing too large over time,
 
            -- especially for players who change dimensions frequently.
 
            -- Example:
 
            -- local MAX_PLAYER_DIM_HISTORY = 5
 
            -- while #DimensionChanges[username] > MAX_PLAYER_DIM_HISTORY do
 
            --     table.remove(DimensionChanges[username], 1)
 
            -- end
 
        end
 
    end
 
end
 
 
 
 
 
-- ============================================================================
 
-- Monitor Rendering Helpers (omitted for brevity)
 
-- ============================================================================
 
 
 
-- Pre-calculate renderers for each column key for cleaner access in WritePlayerData.
 
-- These functions take the processed player data table as input and return the string
 
-- content to be displayed for that column.
 
local ColumnRenderers = {
 
    username = function(p) return p.Username end,
 
    distance = function(p) return string.format("%.1f", p.Distance or 0.0) end, -- Format distance to 1 decimal place
 
    afk = function(p)
 
        -- Display AFK status and ticks if the player is marked as AFK.
 
        if p.IsAFK then
 
            return string.format("AFK (%d)", p.AFKTicks or 0)
 
        else
 
            return "" -- Empty string if not AFK
 
        end
 
    end,
 
    position = function(p)
 
        -- Format the player's current position coordinates.
 
        local pos = p.PlrPos -- Access the original radar position data
 
        return FormatCoordinatesInline(pos and pos.x, pos and pos.y, pos and pos.z) -- Pass nil if pos or coordinate is nil
 
    end,
 
    health = function(p)
 
        -- Format current and max health.
 
        local current = p.PlrPos.health -- Can be nil
 
        local max = p.PlrPos.maxHealth -- Can be nil
 
        -- Handle potential nil values gracefully
 
        if current == nil or max == nil then return "?/?" end
 
        return string.format("%d/%d", current, max)
 
    end,
 
    dimension = function(p)
 
        -- Format the current dimension name.
 
        return FormatDimensionName(p.PlrPos.dimension)
 
    end,
 
    respawn = function(p)
 
        -- Safely access nested respawn position and format.
 
        local rp = p.PlrPos.respawnPosition
 
        return FormatCoordinatesInline(rp and rp.x, rp and rp.y, rp and rp.z) -- Pass nil if rp or coordinate is nil
 
    end,
 
    respawnDim = function(p)
 
        -- Format the respawn dimension name.
 
        return FormatDimensionName(p.PlrPos.respawnDimension)
 
    end,
 
    pitch = function(p)
 
        -- Format pitch to 1 decimal place, default to 0 if nil.
 
        return string.format("%.1f", p.PlrPos.pitch or 0)
 
    end,
 
    yaw = function(p)
 
        -- Format yaw to 1 decimal place, default to 0 if nil.
 
        return string.format("%.1f", p.PlrPos.yaw or 0)
 
    end
 
}
 
 
 
--- Writes a single player's data row to the monitor.
 
-- @param startY The Y coordinate (line number) to start writing on.
 
-- @param playerData The processed player data table containing information for one player.
 
-- @return The next Y coordinate to write on.
 
local function WritePlayerData(startY, playerData)
 
    local currentX = 1 -- Start writing from column 1
 
 
 
    -- 1. Draw Update Indicator (briefly, if configured)
 
    -- Position cursor at the beginning of the line.
 
    Monitor.setCursorPos(currentX, startY)
 
    Monitor.setTextColour(colors.lightGray)
 
    Monitor.write(">") -- Write the indicator character.
 
 
 
    -- If a display delay is configured, pause here to show the indicator.
 
    --[[if CONFIG.INDICATOR_DELAY_SECONDS > 0 then
 
        sleep(CONFIG.INDICATOR_DELAY_SECONDS)
 
    end]]
 
 
 
    -- Move cursor past the indicator space (column 2).
 
    currentX = currentX + 1
 
    Monitor.setCursorPos(currentX, startY)
 
 
 
    -- 2. Write Player Data Columns
 
    for i, colCache in ipairs(ColumnCache) do
 
        -- Determine the text color for this column. Default is the column's defined color.
 
        local currentTextColor = colCache.Color
 
 
 
        -- Apply special coloring rules based on the column key and player data.
 
        if colCache.Key == "afk" and playerData.IsAFK then
 
            currentTextColor = colors.lightGray -- Use a distinct color for AFK status.
 
        elseif colCache.Key == "health" then
 
            -- Get health-based color using the helper function.
 
            currentTextColor = GetHealthColor(playerData.PlrPos.health, playerData.PlrPos.maxHealth)
 
        end
 
        -- Add more `elseif` blocks here for other conditional coloring (e.g., dimension).
 
 
 
        -- Set the text color for the current column.
 
        Monitor.setTextColour(currentTextColor)
 
 
 
        -- Get the text content for this column using the appropriate renderer function.
 
        local renderer = ColumnRenderers[colCache.Key]
 
        local text = renderer and renderer(playerData) or "?" -- Use '?' if renderer is missing (shouldn't happen if setup correctly).
 
 
 
        -- Format the text to fit the column width and alignment, then write it to the monitor.
 
        local formattedText = FormatColumn(text, i)
 
        Monitor.write(formattedText)
 
 
 
        -- The cursor automatically advances, but we can track currentX if needed for more complex layouts.
 
        -- currentX = currentX + #formattedText -- This isn't strictly necessary with Monitor.write
 
 
 
    end -- End of column loop
 
 
 
    -- If no display delay was configured, clear the indicator immediately after writing the row.
 
    if CONFIG.INDICATOR_DELAY_SECONDS <= 0 then
 
        sleep(CONFIG.INDICATOR_DELAY_SECONDS)
 
        
 
        Monitor.setCursorPos(1, startY) -- Go back to column 1
 
        Monitor.setTextColour(colors.black) -- Set text color to match background
 
        Monitor.write(" ") -- Overwrite the indicator with a space
 
    end
 
 
 
    -- Reset text color to white for subsequent writes (like clearLine if used elsewhere, or for safety).
 
    Monitor.setTextColour(colors.white)
 
    -- Monitor.setBackgroundColour(colors.black) -- Assuming default background is black, not always needed here.
 
 
 
    -- Return the Y coordinate for the next line.
 
    return startY + 1
 
end
 
 
 
--- Writes the column headers to the monitor.
 
-- @param y The Y coordinate (line number) to write the header on.
 
-- @return The Y coordinate below the header's separator line.
 
local function WriteHeader(y)
 
    -- Although we start data at column 2, we can use column 1 for the header space
 
    -- to ensure alignment with the data rows that have an indicator space.
 
    -- Monitor.setCursorPos(1, y)
 
    -- Monitor.setTextColour(colors.lightGray) -- Use a different color for the header space indicator
 
    -- Monitor.write(" ") -- Blank space for header indicator column
 
 
 
    local currentX = 2 -- Start header text from column 2 to align with data after indicator
 
 
 
    -- Header Text
 
    Monitor.setCursorPos(currentX, y)
 
    for i, colCache in ipairs(ColumnCache) do
 
        -- Use the column's defined color for its header text.
 
        Monitor.setTextColour(colCache.Color)
 
        -- Write the formatted column name (trimmed and padded).
 
        Monitor.write(FormatColumn(colCache.Name, i))
 
    end
 
 
 
    -- Separator Line below the header
 
    Monitor.setTextColour(colors.white) -- Reset color for the separator
 
    Monitor.setCursorPos(1, y + 1) -- Start separator from column 1
 
    -- Draw a line of dashes that spans the full width of the monitor.
 
    Monitor.write(string.rep("-", MonitorWidth))
 
 
 
    -- Return the Y coordinate for the line below the separator.
 
    return y + 2
 
end
 
 
 
--- Clears all lines on the monitor from a given Y coordinate to the bottom.
 
-- Used to clear old data when the number of players decreases.
 
-- @param startY The first line number to clear.
 
local function ClearRemainingLines(startY)
 
    -- Iterate through each line from startY to the bottom of the monitor.
 
    for y = startY, MonitorHeight do
 
        -- Set the cursor to the beginning of the line.
 
        Monitor.setCursorPos(1, y)
 
        -- Clear the current line.
 
        Monitor.clearLine()
 
    end
 
end
 
 
 
 
 
-- ============================================================================
 
-- Main Display Logic (omitted for brevity)
 
-- ============================================================================
 
 
 
--- Main display function: fetches player data, processes it (distance, AFK),
 
-- sorts, and renders the information to the monitor.
 
local function DisplayPlayerInfo()
 
    -- Ensure the monitor background is black and clear it at the start of each full refresh cycle.
 
    -- This helps prevent ghosting of old data, especially if the number of players changes.
 
    Monitor.setBackgroundColour(colors.black)
 
    --Monitor.clear()
 
 
 
    local currentY = 1 -- Start writing content at the top line (Y=1).
 
 
 
    -- 1. Get Online Players
 
    -- Attempt to get the list of currently online players from the radar.
 
    local onlinePlayers = Radar.getOnlinePlayers()
 
    -- Handle case where the radar failed to return a player list.
 
    if not onlinePlayers then
 
        Monitor.setCursorPos(1, 1)
 
        Monitor.setTextColour(colors.red)
 
        Monitor.write("Error: Could Not Retrieve Player List From Radar.")
 
        -- Clear any other potential content on the screen.
 
        ClearRemainingLines(2)
 
        return -- Exit the function early if player list cannot be retrieved.
 
    end
 
 
 
    -- 2. Process Player Data
 
    local playerDataList = {} -- Table to store processed data for each player.
 
    Statistics.AfkPlayers = 0 -- Reset the AFK count for this scan cycle.
 
    -- Get the detector position for distance calculation.
 
    local detX, detY, detZ = CONFIG.DETECTOR_POS.x, CONFIG.DETECTOR_POS.y, CONFIG.DETECTOR_POS.z
 
 
 
    -- Iterate through the list of online player usernames.
 
    for _, username in ipairs(onlinePlayers) do
 
        -- Get the detailed position data for the current player from the radar.
 
        local plrPos = Radar.getPlayerPos(username)
 
        -- Ensure we got valid position data (at least coordinates) before processing.
 
        if plrPos and plrPos.x ~= nil and plrPos.y ~= nil and plrPos.z ~= nil then
 
            -- Calculate the Euclidean distance from the detector block to the player's position.
 
            local dx = plrPos.x - detX
 
            local dy = plrPos.y - detY
 
            local dz = plrPos.z - detZ
 
            local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
 
 
 
            -- Determine the player's AFK status using the AFK detection logic.
 
            local isAFK = isPlayerAFK(username, plrPos)
 
            -- Increment the global AFK counter if the player is AFK.
 
            if isAFK then Statistics.AfkPlayers = Statistics.AfkPlayers + 1 end
 
 
 
            -- Get the number of unchanged ticks from the PlayerMovement state (will be 0 if not AFK).
 
            local afkTicks = PlayerMovement[username] and PlayerMovement[username].UnchangedTicks or 0
 
 
 
            -- Store the processed data for this player in a table.
 
            table.insert(playerDataList, {
 
                Username = username,    -- Player's username
 
                PlrPos = plrPos,        -- Original radar data (including pitch, yaw, health, respawn etc.)
 
                Distance = distance,    -- Calculated distance from detector
 
                IsAFK = isAFK,          -- Boolean AFK status
 
                AFKTicks = afkTicks     -- Number of ticks considered unchanged/pattern detected
 
            })
 
        else
 
            -- Log a warning if we couldn't get position data for a specific player.
 
             print(string.format("Warning: Could Not Get Position For Player %s", username))
 
             -- Note: These players won't be added to playerDataList and thus not displayed.
 
        end
 
    end
 
 
 
    -- Update the total player count statistic based on the number of players successfully processed.
 
    Statistics.TotalPlayers = #playerDataList
 
 
 
    -- 3. Sort Player Data (Alphabetical by Username, case-insensitive)
 
    table.sort(playerDataList, function(a, b)
 
        return a.Username:lower() < b.Username:lower()
 
    end)
 
 
 
    -- 4. Periodic Reset of Dimension Change Display History
 
    -- Increment the cycle counter and wrap around based on the configured display cycles.
 
    DimensionClearCycle = (DimensionClearCycle + 1) % CONFIG.DIMENSION_CHANGE_DISPLAY_CYCLES
 
    -- If the cycle counter resets to 0, clear the stored dimension change history.
 
    -- This removes old dimension change notifications from the monitor display.
 
    -- The global Statistics.DimensionChanges counter remains unchanged.
 
    if DimensionClearCycle == 0 then
 
        DimensionChanges = {} -- Reset the table containing recent changes for display.
 
    end
 
 
 
 
 
    -- 5. Render to Monitor
 
    -- Calculate the interval for repeating the header to improve readability on tall monitors.
 
    -- Leave space for the header line and the separator line.
 
    local headerRepeatInterval = MonitorHeight - 3
 
    local linesSinceHeader = 0 -- Counter to track lines written since the last header.
 
 
 
    -- Write the initial header at the top of the monitor.
 
    currentY = WriteHeader(currentY)
 
    linesSinceHeader = 0 -- Reset after writing the header.
 
 
 
    -- Iterate through the sorted list of players and write their data to the monitor.
 
    for _, playerData in ipairs(playerDataList) do
 
        -- Check if we have enough vertical space left on the monitor to draw the player's row.
 
        -- We need at least 1 line for the player data, possibly 2 if a dimension change is shown.
 
        if currentY > MonitorHeight then break end -- Stop if we are out of lines.
 
 
 
        -- Repeat the header if the lines written since the last header exceeds the interval
 
        -- AND there is enough space remaining on the monitor to draw a new header and at least one player row.
 
        if linesSinceHeader >= headerRepeatInterval and currentY <= MonitorHeight - 2 then -- Need at least 2 lines below for header + separator
 
             -- Write the repeated header and update the current Y position.
 
            currentY = WriteHeader(currentY)
 
            linesSinceHeader = 0 -- Reset the counter after writing a new header.
 
             -- Re-check for space after potentially writing a new header.
 
            if currentY > MonitorHeight then break end
 
        end
 
 
 
        -- Clear the current line before writing the player's data to overwrite any old content.
 
        Monitor.setCursorPos(1, currentY)
 
        Monitor.clearLine()
 
 
 
        -- Write the current player's data row and get the Y coordinate for the next line.
 
        currentY = WritePlayerData(currentY, playerData)
 
        linesSinceHeader = linesSinceHeader + 1 -- Count the player data line.
 
 
 
        -- Check if there are any recent dimension changes for this player to display.
 
        local changeHistory = DimensionChanges[playerData.Username]
 
        if changeHistory and #changeHistory > 0 then
 
             -- Check for space *before* attempting to write the dimension change line.
 
             if currentY > MonitorHeight then break end
 
 
 
            local latestChange = changeHistory[#changeHistory] -- Get the most recent change.
 
            if latestChange then
 
                -- Clear the line before writing the dimension change info.
 
                Monitor.setCursorPos(1, currentY)
 
                Monitor.clearLine()
 
                -- Indent the dimension change info slightly for visual separation.
 
                Monitor.setCursorPos(3, currentY)
 
                Monitor.setTextColour(colors.red) -- Indicator color for the change line
 
                Monitor.write("> ") -- Indicator
 
                Monitor.setTextColour(colors.blue) -- Use a distinct color for the dimension names.
 
                Monitor.write(string.format("%s -> %s",
 
                    FormatDimensionName(latestChange.FromDimension),
 
                    FormatDimensionName(latestChange.ToDimension)
 
                ))
 
                -- Move to the next line after writing the dimension change.
 
                currentY = currentY + 1
 
                linesSinceHeader = linesSinceHeader + 1 -- Count this line in the header repeat logic.
 
            end
 
        end
 
    end
 
 
 
    -- Clear any remaining lines on the monitor below the last written content.
 
    -- This removes data for players who are no longer online.
 
    ClearRemainingLines(currentY)
 
 
 
 
 
    -- 6. Print Statistics (to console) if interval met.
 
    PrintStatistics()
 
end
 
 
 
-- ============================================================================
 
-- Main Loop & Execution (omitted for brevity)
 
-- ============================================================================
 
 
 
--- Main function to initialize the script, set up parallel tasks, and start the main loops.
 
local function main()
 
    -- Initialize statistic timers using os.time() (seconds since epoch).
 
    Statistics.StartTime = os.time()
 
    Statistics.LastPrintTime = 0 -- Set to 0 to ensure statistics print on the first interval check.
 
 
 
    print("Player Monitor Started.")
 
    print("Initializing Peripherals...")
 
    -- Peripherals were initialized globally at the start, confirm monitor size.
 
    print(string.format("Monitor Size: %d x %d", MonitorWidth, MonitorHeight))
 
    print("Listening For Dimension Changes & Starting Display Loop...")
 
 
 
    -- Run the dimension listener and the main display loop concurrently using parallel.waitForAny.
 
    -- parallel.waitForAny starts multiple functions as separate coroutines. If any of them
 
    -- returns or errors, all others are terminated. This is suitable for a long-running
 
    -- event listener and a main loop.
 
    parallel.waitForAny(
 
        ListenForDimensionChanges, -- Task 1: Dedicated function to listen for dimension change events.
 
        function()                 -- Task 2: Anonymous function wrapper for the main display loop.
 
            -- The main display loop runs indefinitely.
 
            while true do
 
                -- Use pcall to safely call DisplayPlayerInfo. If an error occurs within
 
                -- DisplayPlayerInfo, pcall catches it instead of crashing the script.
 
                local status, err = pcall(DisplayPlayerInfo)
 
                if not status then
 
                    -- If an error occurred (status is false), log it to the console.
 
                    print("Error In DisplayPlayerInfo Loop: " .. tostring(err))
 
                    -- Attempt to display the error message on the monitor.
 
                    Monitor.setBackgroundColour(colors.black) -- Set background to black
 
                    Monitor.setTextColour(colors.red)         -- Set text color to red for errors
 
                    Monitor.clear()                           -- Clear the monitor screen
 
                    Monitor.setCursorPos(1, 1)                -- Go to the top-left corner
 
                    Monitor.write("Runtime Error:\n")         -- Write an error header
 
                    Monitor.write(tostring(err))              -- Write the error message
 
                    -- Pause briefly to allow the user to read the error message before
 
                    -- the loop potentially continues or the script ends (depending on the error).
 
                    sleep(5)
 
                end
 
                -- Add a small sleep duration at the end of each display cycle.
 
                -- This prevents the script from consuming 100% CPU time when the radar
 
                -- updates very quickly or when there are no players. Adjust as needed.
 
                sleep(0.1) -- Sleep for 0.1 seconds.
 
            end
 
        end
 
    )
 
end
 
 
 
-- Start the main execution function.
 
main()
