--[=[
	Server Networker
	Server-side implementation.
]=]

local Players = game:GetService("Players")

local Config = require(script.Parent.Config)
local Promise = require(script.Parent.Promise)

type FunctionMap = {
	[string]: (...any) -> ...any,
}

type ServerNetworkerData = {
	Name: string,

	ServiceFolder: Folder,
	ClientToServerRemote: RemoteFunction,
	ServerToClientRemote: RemoteFunction,

	ServerFunctions: FunctionMap,
	Server: FunctionMap,
	Client: FunctionMap,

	Destroyed: boolean,
}

local Server = {}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end

	return folder :: Folder
end

local function getOrCreateRemoteFunction(parent: Instance, name: string): RemoteFunction
	local remote = parent:FindFirstChild(name)

	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = parent
	end

	return remote :: RemoteFunction
end

local NetworkerServer = {}
NetworkerServer.__index = NetworkerServer

--[=[
	Checks if the networker has been destroyed.
	@return ()
]=]
function NetworkerServer._assertAlive(self: ServerNetworkerData): ()
	assert(not self.Destroyed, `{self.Name} Networker has been destroyed`)
end

--[=[
	Registers a server function that clients can call.
	@param method string -- The method name
	@param callback function -- The callback
	@return ()
]=]
function NetworkerServer._registerServerFunction(
	self: ServerNetworkerData,
	method: string,
	callback: (...any) -> ...any
): ()
	NetworkerServer._assertAlive(self)

	assert(typeof(method) == "string", "Method name must be a string")
	assert(typeof(callback) == "function", `{method} must be a function`)

	self.ServerFunctions[method] = callback
end

--[=[
	Calls a client function.
	@param player Player -- The target player
	@param method string -- The client method name
	@param ... any -- Arguments
	@return Promise
]=]
function NetworkerServer._sendToClient(
	self: ServerNetworkerData,
	player: Player,
	method: string,
	...: any
): any
	NetworkerServer._assertAlive(self)

	assert(player and player:IsA("Player"), "First argument must be a Player")
	assert(typeof(method) == "string", "Method name must be a string")

	local args = table.pack(...)

	return Promise.new(function(resolve, reject)
		task.spawn(function()
			local success, result = pcall(function()
				return self.ServerToClientRemote:InvokeClient(
					player,
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
	Calls a client function on all clients.
	@param method string -- The client method name
	@param ... any -- Arguments
	@return Promise
]=]
function NetworkerServer.SendToAll(
	self: ServerNetworkerData,
	method: string,
	...: any
): any
	NetworkerServer._assertAlive(self)

	assert(typeof(method) == "string", "First argument must be the client method name")

	local args = table.pack(...)
	local promises = {}

	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(
			promises,
			NetworkerServer._sendToClient(
				self,
				player,
				method,
				table.unpack(args, 1, args.n)
			)
		)
	end

	return Promise.all(promises)
end

--[=[
	Calls a client function on all clients except excluded players.
	@param exclusionList { Player } -- Players to exclude
	@param method string -- The client method name
	@param ... any -- Arguments
	@return Promise
]=]
function NetworkerServer.SendToAllBut(
	self: ServerNetworkerData,
	exclusionList: { Player },
	method: string,
	...: any
): any
	NetworkerServer._assertAlive(self)

	assert(typeof(exclusionList) == "table", "First argument must be an exclusion list")
	assert(typeof(method) == "string", "Second argument must be the client method name")

	local excluded = {}

	for _, player in ipairs(exclusionList) do
		excluded[player] = true
	end

	local args = table.pack(...)
	local promises = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if not excluded[player] then
			table.insert(
				promises,
				NetworkerServer._sendToClient(
					self,
					player,
					method,
					table.unpack(args, 1, args.n)
				)
			)
		end
	end

	return Promise.all(promises)
end

--[=[
	Destroys the networker.
	@return ()
]=]
function NetworkerServer.Destroy(self: ServerNetworkerData): ()
	if self.Destroyed then
		return
	end

	self.Destroyed = true

	table.clear(self.ServerFunctions)

	if Config.DestroyRemoteFolderOnServerDestroy and self.ServiceFolder then
		self.ServiceFolder:Destroy()
	end

	table.clear(self :: any)
end

--[=[
	Creates a new server networker.
	@param name string -- The networker name
	@param functions table? -- Optional server functions
	@return any
]=]
function Server.new(name: string, functions: table?): any
	assert(typeof(name) == "string", "Networker name must be a string")
	assert(functions == nil or typeof(functions) == "table", "Functions must be a table")

	local rootFolder = getOrCreateFolder(script.Parent, Config.RemotesFolderName)
	local serviceFolder = getOrCreateFolder(rootFolder, name)

	local clientToServerRemote = getOrCreateRemoteFunction(
		serviceFolder,
		Config.ClientToServerRemoteName
	)

	local serverToClientRemote = getOrCreateRemoteFunction(
		serviceFolder,
		Config.ServerToClientRemoteName
	)

	local self: ServerNetworkerData = {
		Name = name,

		ServiceFolder = serviceFolder,
		ClientToServerRemote = clientToServerRemote,
		ServerToClientRemote = serverToClientRemote,

		ServerFunctions = {},
		Server = {},
		Client = {},

		Destroyed = false,
	}

	if functions then
		for method, callback in pairs(functions) do
			NetworkerServer._registerServerFunction(self, method, callback)
		end
	end

	clientToServerRemote.OnServerInvoke = function(player: Player, method: string, ...: any)
		if self.Destroyed then
			return nil
		end

		if typeof(method) ~= "string" then
			warn("[NetworkerServer] Invalid method name from client:", player)
			return nil
		end

		local callback = self.ServerFunctions[method]

		if not callback then
			if Config.WarnOnMissingHandler then
				warn(`[NetworkerServer] Missing server handler: {method}`)
			end

			return nil
		end

		local success, result = pcall(callback, player, ...)

		if not success then
			warn(`[NetworkerServer] Error in {method}:`, result)
			return nil
		end

		return result
	end

	setmetatable(self.Server, {
		__newindex = function(_, method: string, callback: (...any) -> ...any)
			NetworkerServer._registerServerFunction(self, method, callback)
		end,

		__index = function(_, method: string)
			return self.ServerFunctions[method]
		end,
	})

	setmetatable(self.Client, {
		__index = function(_, method: string)
			return function(player: Player, ...: any)
				return NetworkerServer._sendToClient(self, player, method, ...)
			end
		end,
	})

	return setmetatable(self, {
		__index = function(_, key: string)
			return NetworkerServer[key]
		end,

		__newindex = function(_, key: string, value: any)
			rawset(self :: any, key, value)
		end,
	})
end

return Server