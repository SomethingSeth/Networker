--[=[
	Client Networker
	Client-side implementation.
]=]

local Config = require(script.Parent.Config)
local Promise = require(script.Parent.Promise)

type FunctionMap = {
	[string]: (...any) -> ...any,
}

type ConnectionList = {
	RBXScriptConnection
}

type ClientNetworkerData = {
	Name: string,

	ServiceFolder: Folder?,
	ClientToServerRemote: RemoteFunction?,
	ServerToClientRemote: RemoteFunction?,

	ClientFunctions: FunctionMap,
	Server: FunctionMap,
	Client: FunctionMap,

	Connections: ConnectionList,

	Active: boolean,
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
	Returns a rejected promise with an error message.
	@param message string -- The error message
	@return Promise
]=]
function NetworkerClient._reject(message: string): any
	return Promise.reject(message)
end

--[=[
	Registers a connection so it can be cleaned up later.
	@param connection RBXScriptConnection -- The connection
	@return ()
]=]
function NetworkerClient._addConnection(
	self: ClientNetworkerData,
	connection: RBXScriptConnection
): ()
	table.insert(self.Connections, connection)
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
	Gets the root remotes folder if it exists.
	@return Folder?
]=]
function NetworkerClient._getRootFolder(): Folder?
	local rootFolder = script.Parent:FindFirstChild(Config.RemotesFolderName)

	if rootFolder and rootFolder:IsA("Folder") then
		return rootFolder
	end

	return nil
end

--[=[
	Gets the service folder if it exists.
	@return Folder?
]=]
function NetworkerClient._getServiceFolder(self: ClientNetworkerData): Folder?
	local rootFolder = NetworkerClient._getRootFolder()

	if not rootFolder then
		return nil
	end

	local serviceFolder = rootFolder:FindFirstChild(self.Name)

	if serviceFolder and serviceFolder:IsA("Folder") then
		return serviceFolder
	end

	return nil
end

--[=[
	Attempts to bind the client networker to its remotes.
	@return boolean
]=]
function NetworkerClient._tryBind(self: ClientNetworkerData): boolean
	NetworkerClient._assertAlive(self)

	local serviceFolder = NetworkerClient._getServiceFolder(self)

	if not serviceFolder then
		self.Active = false
		self.ServiceFolder = nil
		self.ClientToServerRemote = nil
		self.ServerToClientRemote = nil

		return false
	end

	local clientToServerRemote = serviceFolder:FindFirstChild(Config.ClientToServerRemoteName)
	local serverToClientRemote = serviceFolder:FindFirstChild(Config.ServerToClientRemoteName)

	if not clientToServerRemote or not clientToServerRemote:IsA("RemoteFunction") then
		self.Active = false
		return false
	end

	if not serverToClientRemote or not serverToClientRemote:IsA("RemoteFunction") then
		self.Active = false
		return false
	end

	self.ServiceFolder = serviceFolder
	self.ClientToServerRemote = clientToServerRemote
	self.ServerToClientRemote = serverToClientRemote
	self.Active = true

	NetworkerClient._bindServerToClientRemote(self)

	return true
end

--[=[
	Binds the server-to-client remote so the server can call client functions.
	@return ()
]=]
function NetworkerClient._bindServerToClientRemote(self: ClientNetworkerData): ()
	local serverToClientRemote = self.ServerToClientRemote

	if not serverToClientRemote then
		return
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
end

--[=[
	Watches for the remotes folder and service folder to be created later.
	@return ()
]=]
function NetworkerClient._watchForRemotes(self: ClientNetworkerData): ()
	local rootFolder = NetworkerClient._getRootFolder()

	if rootFolder then
		local serviceConnection = rootFolder.ChildAdded:Connect(function(child)
			if self.Destroyed then
				return
			end

			if child.Name == self.Name then
				task.defer(function()
					if not self.Destroyed then
						NetworkerClient._tryBind(self)
					end
				end)
			end
		end)

		NetworkerClient._addConnection(self, serviceConnection)
	else
		local rootConnection = script.Parent.ChildAdded:Connect(function(child)
			if self.Destroyed then
				return
			end

			if child.Name ~= Config.RemotesFolderName then
				return
			end

			if not child:IsA("Folder") then
				return
			end

			task.defer(function()
				if not self.Destroyed then
					NetworkerClient._tryBind(self)
				end
			end)

			local serviceConnection = child.ChildAdded:Connect(function(serviceFolder)
				if self.Destroyed then
					return
				end

				if serviceFolder.Name == self.Name then
					task.defer(function()
						if not self.Destroyed then
							NetworkerClient._tryBind(self)
						end
					end)
				end
			end)

			NetworkerClient._addConnection(self, serviceConnection)
		end)

		NetworkerClient._addConnection(self, rootConnection)
	end
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
			if self.Destroyed then
				reject(`{self.Name} Networker has been destroyed`)
				return
			end

			if not self.Active or not self.ClientToServerRemote then
				local didBind = NetworkerClient._tryBind(self)

				if not didBind or not self.ClientToServerRemote then
					reject(`[NetworkerClient] Service is not active: {self.Name}`)
					return
				end
			end

			local success, result = pcall(function()
				return (self.ClientToServerRemote :: RemoteFunction):InvokeServer(
					method,
					table.unpack(args, 1, args.n)
				)
			end)

			if success then
				resolve(result)
			else
				self.Active = false
				reject(result)
			end
		end)
	end)
end

--[=[
	Returns whether this client networker is currently bound to server remotes.
	@return boolean
]=]
function NetworkerClient.IsActive(self: ClientNetworkerData): boolean
	if self.Destroyed then
		return false
	end

	if self.Active then
		return true
	end

	return NetworkerClient._tryBind(self)
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
	self.Active = false

	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end

	table.clear(self.Connections)
	table.clear(self.ClientFunctions)
	table.clear(self.Server)
	table.clear(self.Client)
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

	local self: ClientNetworkerData = {
		Name = name,

		ServiceFolder = nil,
		ClientToServerRemote = nil,
		ServerToClientRemote = nil,

		ClientFunctions = {},
		Server = {},
		Client = {},

		Connections = {},

		Active = false,
		Destroyed = false,
	}

	if functions then
		for method, callback in pairs(functions) do
			NetworkerClient._registerClientFunction(self, method, callback)
		end
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

	NetworkerClient._tryBind(self)
	NetworkerClient._watchForRemotes(self)

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