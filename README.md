
<div align="center">
	<h1>Roblox Networker</h1>
	<p>Roblox Remote wrapper that uses service-styled function calls.</p>
</div>


Networker uses evaera's [Promise](https://github.com/evaera/roblox-lua-promise/tree/master) so that remote calls can return asynchronously without yielding the rest of the code.  

<div align="center">
	<h1>Example Usage</h1>
</div>

## Server
```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerNetworker = require(ReplicatedStorage.Shared.Networker)

local ExampleService = {
	Networker = ServerNetworker.new("ExampleService")
}

-- Server exposes this function to the client; client can call it. 
function ExampleService.Networker.Server.Message(player, message)
	print(player.Name .. " sent message to server:", message)

	return "message received by server"
end

-- Sending a message by calling the client function from the server.
function ExampleService.SendMessage(player)
	ExampleService.Networker.Client.Message(player, "Hello from the server!") 
		:andThen(function(response)
			print("Client response:", response)
		end)
		:catch(function(err)
			warn("Failed to send message:", err)
		end)
end

-- Send message on player join.
function  ExampleService:PlayerAdded(player)  
	task.wait(2)  
  
	self.SendMessage(player)  
end  
  
Players.PlayerAdded:Connect(function(player)  
	ExampleService:PlayerAdded(player)  
end)

return ExampleService



```

## Client

```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientNetworker = require(ReplicatedStorage.Shared.Networker)

local player = Players.LocalPlayer

local ExampleServiceClient = {
	Networker = ClientNetworker.new("ExampleService")
}

-- Client function that the server can call.
function ExampleServiceClient.Networker.Client.Message(message)
	print("Message received from server:", message)
	return "Responding from the client!"
end

-- Sending a message by calling the server function from the client.
function ExampleServiceClient:SendMessage()
	self.Networker.Server.Message("Hello from the client!")
		:andThen(function(response)
			print("Server response:", response)
		end)
		:catch(function(err)
			warn("Failed to send message:", err)
		end)
end

ExampleServiceClient:SendMessage()

return ExampleServiceClient
```