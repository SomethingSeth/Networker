--[=[
	Types
]=]

export type Promise<T... = ...any> = any

export type NetworkFunction = (...any) -> ...any

export type FunctionMap = {
	[string]: NetworkFunction,
}

export type ServerNetworker = {
	Name: string,

	Server: FunctionMap,
	Client: FunctionMap,

	SendToAll: (self: ServerNetworker, method: string, ...any) -> Promise<any>,
	SendToAllBut: (self: ServerNetworker, exclusionList: { Player }, method: string, ...any) -> Promise<any>,
	Destroy: (self: ServerNetworker) -> (),

	[string]: any,
}

export type ClientNetworker = {
	Name: string,

	Server: FunctionMap,
	Client: FunctionMap,

	Destroy: (self: ClientNetworker) -> (),

	[string]: any,
}

export type Networker = ServerNetworker | ClientNetworker

return {}