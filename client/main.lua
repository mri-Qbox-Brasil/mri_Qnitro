local config = require 'config.client'
local nitrousActivated = false
local nitrousBoost = config.nitrousBoost
local nitroDelay = false
local PurgeLoop = false

local function setMultipliers(vehicle, disable)
    local multiplier = disable and 1.0 or nitrousBoost
    SetVehicleEnginePowerMultiplier(vehicle, multiplier)
    SetVehicleEngineTorqueMultiplier(vehicle, multiplier)
end

local function stopBoosting()
    SetVehicleBoostActive(cache.vehicle, false)
    setMultipliers(cache.vehicle, true)
    Entity(cache.vehicle).state:set('nitroFlames', false, true)
    -- StopScreenEffect('RaceTurbo')
    nitrousActivated = false
end

local function nitrousUseLoop()
    nitrousActivated = true
    nitroDelay = true
    SetTimeout(3000, function()
        nitroDelay = false
    end)
    local vehicleState = Entity(cache.vehicle).state
    SetVehicleBoostActive(cache.vehicle, true)
    CreateThread(function()
        while nitrousActivated and cache.vehicle do
            if vehicleState.nitro - 0.25 >= 0 then
                setMultipliers(cache.vehicle, false)
                SetEntityMaxSpeed(cache.vehicle, 999.0)
                -- StartScreenEffect('RaceTurbo', 0, false)
                vehicleState:set('nitro', vehicleState.nitro - 0.25, true)
                vehicleState:set('nitroPurge', (vehicleState.nitroPurge or 0) + 1, true)
                if vehicleState.nitroPurge >= 100 then
                    exports.qbx_core:Notify(locale('notify.needs_purge'), 'error')
                    stopBoosting()
                end
            else
                stopBoosting()
                vehicleState:set('nitro', 0, true)
            end
            Wait(100)
        end
    end)
end

local function stopPurging()
    local vehicleState = Entity(cache.vehicle).state
    vehicleState:set('purgeNitro', false, true)
    PurgeLoop = false
end

local function nitrousPurgeLoop()
    local vehicleState = Entity(cache.vehicle).state
    PurgeLoop = true
    CreateThread(function()
        while PurgeLoop and cache.vehicle do
            if vehicleState.nitroPurge - 1 >= 0 then
                vehicleState:set('nitroPurge', vehicleState.nitroPurge - 1, true)
            else
                vehicleState:set('nitroPurge', 0, true)
                stopPurging()
            end
            Wait(100)
        end
    end)
end

qbx.entityStateHandler('nitroFlames', function(veh, netId, value)
    if not veh or not DoesEntityExist(veh) then return end
    RemoveNamedPtfxAsset("veh_xs_vehicle_mods")

    RequestNamedPtfxAsset("veh_xs_vehicle_mods")
    RequestPtfxAsset("veh_xs_vehicle_mods")

    SetVehicleNitroEnabled(veh, value)
    -- EnableVehicleExhaustPops(veh, value)
    SetVehicleBoostActive(veh, value)
end)

local purge = {}
qbx.entityStateHandler('purgeNitro', function(veh, netId, value)
    if not veh or not DoesEntityExist(veh) then return end

    if not value then
        local currentPurge = purge[veh]
        if currentPurge?.left then
            StopParticleFxLooped(currentPurge.left, false)
        end
        if currentPurge?.right then
            StopParticleFxLooped(currentPurge.right, false)
        end
        purge[veh] = nil
        return
    end

    local bone
    local pos
    local off

    bone = GetEntityBoneIndexByName(veh, 'bonnet')
    if bone == -1 then
        bone = GetEntityBoneIndexByName(veh, 'engine')
    end

    pos = GetWorldPositionOfEntityBone(veh, bone)
    off = GetOffsetFromEntityGivenWorldCoords(veh, pos.x, pos.y, pos.z)

    if bone == GetEntityBoneIndexByName(veh, 'bonnet') then
        off += vec3(0.0, 0.05, 0)
    else
        off += vec3(0.0, -0.2, 0.2)
    end

    UseParticleFxAssetNextCall('core')
    local leftPurge = StartParticleFxLoopedOnEntity('ent_sht_steam', veh, off.x - 0.5, off.y, off.z, 40.0, -20.0, 0.0, 0.3, false, false, false)
    UseParticleFxAssetNextCall('core')
    local rightPurge = StartParticleFxLoopedOnEntity('ent_sht_steam', veh, off.x + 0.5, off.y, off.z, 40.0, 20.0, 0.0, 0.3, false, false, false)
    purge[veh] = {left = leftPurge, right = rightPurge}
end)

local nitrousKeybind = lib.addKeybind({
    name = 'nitrous',
    description = 'Use Nitrous',
    defaultKey = 'LCONTROL',
    disabled = true,
    onPressed = function(_)
        if not cache.vehicle then return end
        local vehicleState = Entity(cache.vehicle).state
        if nitroDelay or nitrousActivated then return end
        if (vehicleState?.nitro or 0) > 0 and (vehicleState.nitroPurge or 0) < 100 then
            vehicleState:set('nitroFlames', true, true)
            nitrousUseLoop()
        end
    end,
    onReleased = function(_)
        if not cache.vehicle then return end
        stopBoosting()
    end
})

local purgeKeybind = lib.addKeybind({
    name = 'purge',
    description = 'Purge Nitrous',
    defaultKey = 'LSHIFT',
    disabled = true,
    onPressed = function(_)
        if not cache.vehicle then return end
        local vehicleState = Entity(cache.vehicle).state
        if not nitrousActivated and (vehicleState?.nitroPurge or 0) > 0 then
            vehicleState:set('purgeNitro', true, true)
            nitrousPurgeLoop()
        end
    end,
    onReleased = function(_)
        if not cache.vehicle then return end
        stopPurging()
    end
})


lib.onCache('seat', function(seat)
    nitrousKeybind:disable(seat ~= -1)
    purgeKeybind:disable(seat ~= -1)
    if seat ~= -1 then
        NitrousLoop = false
        return
    end

    if config.turboRequired and not IsToggleModOn(cache.vehicle, 18) then return end
end)

lib.onCache('vehicle', function(vehicle)
    if not vehicle then
        if nitrousActivated then
            nitrousActivated = false
            stopBoosting()
        end
        if PurgeLoop then
            PurgeLoop = false
            stopPurging()
        end
    end
end)

lib.callback.register('qbx_nitro:client:LoadNitrous', function()
    if not cache.vehicle or IsThisModelABike(cache.vehicle) then
        exports.qbx_core:Notify(locale('notify.not_in_vehicle'), 'error')
        return false
    end

    if config.turboRequired and not IsToggleModOn(cache.vehicle, 18) then
        exports.qbx_core:Notify(locale('notify.need_turbo'), 'error')
        return false
    end

    if cache.seat ~= -1 then
        exports.qbx_core:Notify(locale('notify.must_be_driver'), 'error')
        return false
    end

    local vehicleState = Entity(cache.vehicle).state
    if vehicleState.nitro and vehicleState.nitro > 0 then
        exports.qbx_core:Notify(locale('notify.already_have_nos'), 'error')
        return false
    end

    if lib.progressBar({
            duration = 2500,
            label = locale('progress.connecting'),
            useWhileDead = false,
            canCancel = true,
            disable = {
                combat = true
            }
    }) then -- if completed
        return VehToNet(cache.vehicle)
    else    -- if canceled
        exports.qbx_core:Notify(locale('notify.canceled'), 'error')
        return false
    end
end)



-- Enable Global Slipstream
local SyncStop = false

CreateThread(function()
    Wait(1000)
    SetEnableVehicleSlipstreaming(true)
    if true then 
        print("Slip Stream Enabled")
    end
end)

-- Global Loop
CreateThread(function()
    while true do 
        Wait(1000)
        local myped = PlayerPedId()
        if IsPedInAnyVehicle(myped, false) then 
            local mycar = GetVehiclePedIsIn(myped, false)
            local slip = nitrousActivated --IsVehicleSlipstreamLeader(mycar) == 1
            if slip then
                if SyncStop then
                    SyncStop = false
                end
                TriggerServerEvent('slipstream:sync', true, NetworkGetNetworkIdFromEntity(mycar))
            else
                if not SyncStop then
                    TriggerServerEvent('slipstream:sync', false, NetworkGetNetworkIdFromEntity(mycar))
                    SyncStop = true
                end
            end
            local slipam = GetVehicleCurrentSlipstreamDraft(GetVehiclePedIsIn(PlayerPedId(),false))
            if slipam > 1.0 then 
                ShakeGameplayCam('SKY_DIVING_SHAKE', 0.75)
            else
                StopGameplayCamShaking(true)
            end
        end
    end
end)

RegisterNetEvent('slipstream:client:sync',function(enabled,car)
    if not NetworkDoesEntityExistWithNetworkId(car) then return end -- neen sync
    local veh = NetworkGetEntityFromNetworkId(car)
    SetVehicleLightTrailEnabled(veh,enabled)
end)

-- trails code from : https://github.com/swcfx/sw-nitro/blob/master/client/trails.lua

local vehicles = {}
local particles = {}

function IsVehicleLightTrailEnabled(vehicle)
    return vehicles[vehicle] == true
end

function SetVehicleLightTrailEnabled(vehicle, enabled)
    if IsVehicleLightTrailEnabled(vehicle) == enabled then return end
    if enabled then
        local ptfxs = {}
        local leftTrail = CreateVehicleLightTrail(vehicle, GetEntityBoneIndexByName(vehicle, "taillight_l"), 1.0)
        local rightTrail = CreateVehicleLightTrail(vehicle, GetEntityBoneIndexByName(vehicle, "taillight_r"), 1.0)
        ptfxs[#ptfxs+1] = leftTrail
        ptfxs[#ptfxs+1] = rightTrail
        vehicles[vehicle] = true
        particles[vehicle] = ptfxs
    else
        if particles[vehicle] and #particles[vehicle] > 0 then
            for _, particleId in ipairs(particles[vehicle]) do
                StopVehicleLightTrail(particleId, 500)
            end
        end
        vehicles[vehicle] = nil
        particles[vehicle] = nil
    end
end

function CreateVehicleLightTrail(vehicle, bone, scale)
    UseParticleFxAssetNextCall('core')
    local ptfx = StartParticleFxLoopedOnEntityBone('veh_light_red_trail', vehicle, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, bone, scale, false, false, false)
    SetParticleFxLoopedEvolution(ptfx, "speed", 1.0, false)
    return ptfx
end

function StopVehicleLightTrail(ptfx, duration)
    CreateThread(function()
      local endTime = GetGameTimer() + duration
      while GetGameTimer() < endTime do 
        Wait(0)
        local now = GetGameTimer()
        local scale = (endTime - now) / duration
        SetParticleFxLoopedScale(ptfx, scale)
        SetParticleFxLoopedAlpha(ptfx, scale)
      end
      StopParticleFxLooped(ptfx)
    end)
end