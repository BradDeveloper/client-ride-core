local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local RideFolder = ReplicatedStorage:WaitForChild("Ride")
local Event_Seat = RideFolder:WaitForChild("Sit")

local PrimaryPartHandler = require(script.Parent.PrimaryPartHandler)
local TargetHandler = require(script.Parent.TargetHandler)
local GunHandler = require(script.Parent.GunHandler)

local Train = RideFolder:WaitForChild("Train")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local function calculateCenterOffset(model,p0,p1)
	return p0.CFrame:lerp(p1.CFrame,0.5):ToObjectSpace(model.PrimaryPart.CFrame)
end

local TRAIN_OFFSET = calculateCenterOffset(Train.Body,Train.Body.Front,Train.Body.Back)
local ROTATION_OFFSET = Train.Rot:GetPrimaryPartCFrame():ToObjectSpace(Train.PrimaryPart.CFrame):inverse()

local COMPILED_DATA = require(ReplicatedStorage.Ride.CompiledData)
local TOTAL_LENGTH = 77.2

local RECORDING = false

local m = {}
m.Carts = {}

local compiledData = {}

local Cart = {}
Cart.__index = Cart
m.Cart = Cart

function m:init()
	m.render()
	TargetHandler:init()
	return true
end

local function map(n, start, stop, nStart, nStop, folBounds)
	local v = ((n - start) / (stop - start)) * (nStop - nStart) + nStart
	
	if not folBounds then
		return v
	else
		return math.clamp(v, nStart, nStop)	
	end
end

local function getNormalizedP()
	local position = Vector2.new(Mouse.X, Mouse.Y)
	local size = Vector2.new(Mouse.ViewSizeX, Mouse.ViewSizeY)
	return ((size/2)-position)/30
end

local function getClosestNode(t)
	for i,time in pairs(COMPILED_DATA) do
		if t <= time then
			return time,i,COMPILED_DATA[i+1]
		end
	end
	return 0,1,COMPILED_DATA[2]
end

local function createCart(cf)
	local c = Train:Clone()
	c.Name = "TRAIN"
	c.Parent = game.Workspace
	
	local primary = PrimaryPartHandler.new(c.Body)
	primary:SetPrimaryPartCFrame(cf)
	return c,primary
end

function m.render()
	local function fire(t,step)
		for _, cart in pairs(m.Carts) do
			cart:update(step)
		end
	end
	RunService.Stepped:Connect(fire)
end

function Cart.new(points,car,start,current)
	local c,primary = car,PrimaryPartHandler.new(car.Body)--createCart(points[1])
	local rotP = PrimaryPartHandler.new(c.Rot)
	--local gunP = PrimaryPartHandler.new(c.Gun)
	
	primary:SetPrimaryPartCFrame(points[1])
	
	local offset = current-start
	local closest,start_point,next = getClosestNode(offset)
	
	local point = map(offset,closest,next,0,1,true)

	local self = {
		type = 0,
		start = start,
		t = point,
		curI = start_point;
		lp = points[start_point],
		p = points[start_point+1],
		cf = CFrame.new(),
		points = points,
		cart = c,
		rot = c.Rot,
		gun = nil,
		primaryClass = primary,
		rotPrimary = rotP,
		--gunPrimary = gunP,
		guns = {},
		rotDeg = 0,
		isTimeout = false,
		speed = 10,
		occupied = false,
	}
	setmetatable(self,Cart)
	table.insert(m.Carts,self)
	
	local s = self.rot.Seats
	for _,seat in pairs(s:GetChildren()) do
		local gun = seat:FindFirstChild("Gun") and seat.Gun.Value
		if gun then
			local data = {["Primary"]=PrimaryPartHandler.new(gun),["Offset"]=gun:GetPrimaryPartCFrame():ToObjectSpace(seat.CFrame):inverse(),["Seat"]=seat}
			self.guns[gun] = data
		end
	end
	
	return self
end

function Cart:update(deltaTime)
	if self.t >= 1 then
		if self.curI == table.getn(self.points)-1 then
			self.curI = 0
			table.remove(m.Carts,table.find(m.Carts,self))
			self.cart:Destroy()
			--print(table.concat(compiledData,","))
			return true
		end
		self.t = 0 
		self.lp = self.p
		self.curI=self.curI+1
		
		if RECORDING then
			table.insert(compiledData,workspace.DistributedGameTime-self.start)
		end
		
		if self.occupied then
			TargetHandler:newPoint(self.curI)
		end
		
		self.p = self.points[self.curI]
	end
	
	if not self.isTimeout then
		local distance = (self.lp.p-self.p.p).magnitude
		self.t = self.t+1/distance*self.speed*deltaTime
		self.primaryClass:SetPrimaryPartCFrame(self.lp:lerp(self.p,self.t)*TRAIN_OFFSET)
	end
	
	self.rotDeg = self.rotDeg+45*deltaTime
	self.rotPrimary:SetPrimaryPartCFrame(self.cart.Body.PrimaryPart.CFrame*ROTATION_OFFSET*CFrame.Angles(0,math.rad(self.rotDeg),0))
	
	if self.occupied then
		if self.type == 0 then
			if Camera.CameraType ~= Enum.CameraType.Scriptable then
				Camera.CameraType = Enum.CameraType.Scriptable
				Camera.FieldOfView = 90
			end
			
			local norm = getNormalizedP()
			local cameraAngle = CFrame.Angles(math.rad(norm.Y),math.rad(norm.X),0)
			
			local gunAngle = CFrame.Angles(math.rad(math.clamp(norm.Y,-7,1000)),math.rad(norm.X*2),math.rad(norm.X*-1/5))
			self.gun.Primary:SetPrimaryPartCFrame(self.gun.Seat.CFrame*gunAngle*self.gun.Offset)
			
			Camera.CFrame = self.gun.Seat.CFrame*CFrame.new(0,3,0)*cameraAngle
		end
	end
	if self.type == 0 then
		for _,gun in pairs(self.guns) do
			if self.gun ~= gun then
				gun.Primary:SetPrimaryPartCFrame(gun.Seat.CFrame*gun.Offset)
			end
		end
	end
end

function Cart:timeout(duration)
	self.isTimeout = true
	wait(duration)
	self.isTimeout = false
end

function Cart:sit(seat)
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	wait(0.1)
	print("Sitting")
	
	if self.type == 0 then
		--handle gun
		local gun = seat.Gun.Value
		self.gun = self.guns[gun]
		GunHandler:new(gun)
		
		--apply character data
		local fakeArms = gun.FakeArm
		if fakeArms:FindFirstChild("Left Arm") then
			fakeArms["Left Arm"].Transparency = 0
		end
	end
	
	self.occupied = true
	--Camera.CameraType = Enum.CameraType.Scriptable
	--Camera.CFrame = self.primaryClass:GetPrimaryPartCFrame()
	
	for _, p in pairs(character:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = 1	
		end
	end
	--character.Humanoid:RemoveAccessories()
	
	self.seat = seat
end

local function getCartClassFromCar(car)
	for _,cart in pairs(m.Carts) do
		if cart.cart == car then
			return cart
		end
	end
end

local function sitEvent(seat)
	local cart = seat:FindFirstAncestor("Train")
	local class = getCartClassFromCar(cart)
	if class then
		class:sit(seat)
	end
end

Event_Seat.OnClientEvent:Connect(sitEvent)

return m