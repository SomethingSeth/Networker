--[=[
	Client Networker
	Client-side implementation.
]=]

local Config = require(script.Parent.Config)
local Promise = require(script.Parent.Promise).Get()

type FunctionMap = {
	[string]: (...any) -> ...any,
}

type ClientNetworkerData = {
	Name: string,

	ServiceFolder: Folder,
	ClientToServerRemote: RemoteFunction,
	ServerToClientRemote: RemoteFunction,

	ClientFunctions: FunctionMap,
	Server: FunctionMap,
	Client: FunctionMap,

	Destroyed: boolean,
}

local Client = {}

local NetworkerClient = {}
NetworkerClient.__index = NetworkerClient

--[=[
	Checks if the networker has been destroyed.
	@return ()
]=]
function NetworkerClient._assertAlive(self: ClientNetworkerData): ()
	assert(not self.Destroyed, `{self.Name} Networker has been destroyed`)
end

--[=[
	Registers a client function that the server can call.
	@param method string -- The method name
	@param callback function -- The callback
	@return ()
]=]
function NetworkerClient._registerClientFunction(
	self: ClientNetworkerData,
	method: string,
	callback: (...any) -> ...any
): ()
	NetworkerClient._assertAlive(self)

	assert(typeof(method) == "string", "Method name must be a string")
	assert(typeof(callback) == "function", `{method} must be a function`)

	self.ClientFunctions[method] = callback
end

--[=[
	Calls a server function.
	@param method string -- The server method name
	@param ... any -- Arguments
	@return Promise
]=]
function NetworkerClient._sendToServer(
	self: ClientNetworkerData,
	method: string,
	...: any
): any
	NetworkerClient._assertAlive(self)

	assert(typeof(method) == "string", "Method name must be a string")

	local args = table.pack(...)

	return Promise.new(function(resolve, reject)
		task.spawn(function()
			local success, result = pcall(function()
				return self.ClientToServerRemote:InvokeServer(
					method,
					table.unpack(args, 1, args.n)
				)
			end)

			if success then
				resolve(result)
			else
				reject(result)
			end
		end)
	end)
end

--[=[
	Destroys the networker.
	@return ()
]=]
function NetworkerClient.Destroy(self: ClientNetworkerData): ()
	if self.Destroyed then
		return
	end

	self.Destroyed = true

	table.clear(self.ClientFunctions)
	table.clear(self :: any)
end

--[=[
	Creates a new client networker.
	@param name string -- The networker name
	@param functions table? -- Optional client functions
	@return any
]=]
function Client.new(name: string, functions: table?): any
	assert(typeof(name) == "string", "Networker name must be a string")
	assert(functions == nil or typeof(functions) == "table", "Functions must be a table")

	local rootFolder = script.Parent:WaitForChild(Config.RemotesFolderName)
	local serviceFolder = rootFolder:WaitForChild(name)

	local clientToServerRemote = serviceFolder:WaitForChild(Config.ClientToServerRemoteName) :: RemoteFunction
	local serverToClientRemote = serviceFolder:WaitForChild(Config.ServerToClientRemoteName) :: RemoteFunction

	local self: ClientNetworkerData = {
		Name = name,

		ServiceFolder = serviceFolder,
		ClientToServerRemote = clientToServerRemote,
		ServerToClientRemote = serverToClientRemote,

		ClientFunctions = {},
		Server = {},
		Client = {},

		Destroyed = false,
	}

	if functions then
		for method, callback in pairs(functions) do
			NetworkerClient._registerClientFunction(self, method, callback)
		end
	end

	serverToClientRemote.OnClientInvoke = function(method: string, ...: any)
		if self.Destroyed then
			return nil
		end

		if typeof(method) ~= "string" then
			warn("[NetworkerClient] Invalid method name from server")
			return nil
		end

		local callback = self.ClientFunctions[method]

		if not callback then
			if Config.WarnOnMissingHandler then
				warn(`[NetworkerClient] Missing client handler: {method}`)
			end

			return nil
		end

		local success, result = pcall(callback, ...)

		if not success then
			warn(`[NetworkerClient] Error in {method}:`, result)
			return nil
		end

		return result
	end

	setmetatable(self.Client, {
		__newindex = function(_, method: string, callback: (...any) -> ...any)
			NetworkerClient._registerClientFunction(self, method, callback)
		end,

		__index = function(_, method: string)
			return self.ClientFunctions[method]
		end,
	})

	setmetatable(self.Server, {
		__index = function(_, method: string)
			return function(...: any)
				return NetworkerClient._sendToServer(self, method, ...)
			end
		end,
	})

	return setmetatable(self, {
		__index = function(_, key: string)
			return NetworkerClient[key]
		end,

		__newindex = function(_, key: string, value: any)
			rawset(self :: any, key, value)
		end,
	})
end

return Client