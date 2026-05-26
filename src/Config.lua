--[=[
	Config
	Controls remote names and Promise loading.
]=]

return {
	RemotesFolderName = "_remotes",

	ClientToServerRemoteName = "ClientToServer",
	ServerToClientRemoteName = "ServerToClient",

	SharedFolderName = "Shared",
	PromiseModuleName = "Promise",

	PromiseAssetId = 4815792109,

	WarnOnMissingHandler = true,
	DestroyRemoteFolderOnServerDestroy = true,
}