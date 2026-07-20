--[[
				Owl - RateLimiter
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local Players = game:GetService("Players")

--

local DefaultWindow = 1
local DefaultWarnCooldown = 5
local DefaultCleanup = 30
local DefaultBanDuration = 30

--

local RateLimiter = {}

-- > // Types \\ < --

type PlayerRecord = {
	timestamp: {number},
	warnedAt: number,
	violations: number,
	bannedUntil: number,
}

--

export type PenaltyConfig = {
	enabled: boolean,
	warnThreshold: number?,
	kickThreshold: number?,
	banThreshold: number?,
	banDuration: number?,
	kickMessage: string?,
	banMessage: string?,
}

--

export type RateLimiterOptions = {
	maxCalls: number,
	window: number?,
	global: boolean?,
	warnCooldown: number?,
	label: string?,
	penalty: PenaltyConfig?,
}

-- > // Func : New \\ < --

function RateLimiter.new(opts: RateLimiterOptions): (plr: Player, args: {any}) -> (boolean, ...any)
	assert(type(opts) == "table", "[Owl - RateLimiter] opts must be a table.")
	assert(type(opts.maxCalls) == "number" and opts.maxCalls > 0, "[Owl - RateLimiter] maxCalls must be a positive number.")
	
	local maxCalls = opts.maxCalls
	local window = opts.window or DefaultWindow
	local isGlobal = opts.global or false
	local warnCooldown = opts.warnCooldown or DefaultWarnCooldown
	local label = opts.label or "remote"
	
	local pen = opts.penalty or { enabled = false }
	local penaltyOn = pen.enabled == true
	local warnThresh = pen.warnThreshold or 3
	local kickThresh = pen.kickThreshold or 10
	local banThresh = pen.banThreshold or 20
	local banDuration = pen.banDuration or DefaultBanDuration
	local kickMsg = pen.kickMessage or "[Owl] Too many requests."
	local banMsg = pen.banMessage or "[Owl] Banned temporarely for spamming requests."
	
	local records:  {[number]: PlayerRecord} = {}
	local lastCleanup: number = os.clock()
	
	local function getRecord(key: number): PlayerRecord
		if not records[key] then
			records[key] = {
				timestamps = {},
				warnedAt = 0,
				violations = 0,
				bannedUntil = 0,
			}
		end
		
		return records[key]
	end
	
	local function pruneAndCount(record: PlayerRecord, now: number): number
		local cutoff = now - window
		local fresh: {number} = {}

		for _, t in ipairs(record.timestamps) do
			if t > cutoff then
				table.insert(fresh, t)
			end
		end

		record.timestamps = fresh
		return #fresh
	end
	
	local function cleanupStale(now: number)
		local threshold = now - (window * 2)

		for key, record in pairs(records) do
			local latest = record.timestamps[#record.timestamps]
			
			if (not latest or latest < threshold) and record.bannedUntil < now then
				records[key] = nil
			end
		end
	end
	
	local function applyPenalty(plr: Player, record: PlayerRecord, now: number)
		if not penaltyOn then return end
		record.violations += 1
		local v = record.violations

		if v >= banThresh then
			record.bannedUntil = now + banDuration
			warn(("[Owl - RateLimiter] %s (%d) banned for %ds on %q (%d violations)."):format(plr.Name, plr.UserId, banDuration, label, v))
			
			task.defer(function()
				if plr and plr.Parent then
					plr:Kick(banMsg)
				end
			end)
			
			return
		end

		if v >= kickThresh then
			warn(("[Owl - RateLimiter] %s (%d) kicked on %q (%d violations)."):format(plr.Name, plr.UserId, label, v))
			
			task.defer(function()
				if plr and plr.Parent then
					plr:Kick(kickMsg)
				end
			end)
			
			return
		end

		if v >= warnThresh and now - record.warnedAt > warnCooldown then
			record.warnedAt = now
			warn(("[Owl - RateLimiter] %s (%d) — %d violations on %q."):format(plr.Name, plr.UserId, v, label))
		end
	end
	
	Players.PlayerRemoving:Connect(function(plr: Player)
		if not isGlobal then
			records[plr.UserId] = nil
		end
	end)
	
	return function(plr: Player, _args: {any}): (boolean, ...any)
		local now = os.clock()

		if now - lastCleanup > DefaultCleanup then
			cleanupStale(now)
			lastCleanup = now
		end

		local key = isGlobal and 0 or plr.UserId
		local record = getRecord(key)

		if record.bannedUntil > now then
			local remaining = math.ceil(record.bannedUntil - now)
			warn(("[Owl - RateLimiter] %s (%d) tried %q while banned (%ds left)."):format(plr.Name, plr.UserId, label, remaining))
			return false
		end

		local count = pruneAndCount(record, now)

		if count >= maxCalls then
			applyPenalty(plr, record, now)

			if not penaltyOn and now - record.warnedAt > warnCooldown then
				record.warnedAt = now

				if isGlobal then
					warn(("[Owl - RateLimiter] Global rate limit hit on %q — %d/%d in %.1fs."):format(label, count, maxCalls, window))
				else
					warn(("[Owl - RateLimiter] %s (%d) hit rate limit on %q — %d/%d in %.1fs."):format(plr.Name, plr.UserId, label, count, maxCalls, window))
				end
			end

			return false
		end

		table.insert(record.timestamps, now)
		return true
	end
end

-- > // Func : Per Plr \\ < --

function RateLimiter.perPlayer(maxCalls: number, window: number?, label: string?, penalty: PenaltyConfig?): (plr: Player, args: {any}) -> (boolean, ...any)
	return RateLimiter.new({
		maxCalls = maxCalls,
		window = window,
		global = false,
		label = label or "remote",
		penalty = penalty,
	})
end

-- > // Func : Global \\ < --

function RateLimiter.global(maxCalls: number, window: number?, label: string?, penalty: PenaltyConfig?): (plr: Player, args: {any}) -> (boolean, ...any)
	return RateLimiter.new({
		maxCalls = maxCalls,
		window = window,
		global = true,
		label = label or "remote",
		penalty = penalty,
	})
end

-- > // Func : Strict \\ < --

function RateLimiter.strict(maxCalls: number, window: number?, label: string?): (plr: Player, args: {any}) -> (boolean, ...any)
	return RateLimiter.new({
		maxCalls = maxCalls,
		window = window,
		global = false,
		label = label or "remote",
		penalty  = {
			enabled = true,
			warnThreshold = 2,
			kickThreshold = 5,
			banThreshold = 10,
			banDuration = 60,
			kickMessage = "[Owl] Kick for spamming requests.",
			banMessage = "[Owl] Ban 60s for spamming requests.",
		},
	})
end

return RateLimiter