--[=[
	Networker
]=]

local RunService = game:GetService("RunService")

local Networker = {}

--[=[
	Creates a new networker.
	@param name string -- The networker name
	@param functions table? -- Optional functions
	@return any
]=]
function Networker.new(name: string, functions: table?): any
	if RunService:IsClient() then
		local Client = require(script.Client)
		return Client.new(name, functions)
	end

	local Server = require(script.Server)
	return Server.new(name, functions)
end

return Networker