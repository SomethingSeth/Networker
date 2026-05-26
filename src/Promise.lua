--[=[
	Promise Loader
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = {}

--[=[
	Gets ReplicatedStorage.Packages.Promise.
	@return any
]=]
function Promise.Get(): any
	local promise = ReplicatedStorage.Packages:FindFirstChild("Promise")

	if not promise then
		error("[Networker] Promise module not found in ReplicatedStorage.Packages")
	end

	return require(promise)
end

return Promise