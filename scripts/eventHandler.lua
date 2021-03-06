local eventHandler = {}

commandHandler = require("commandHandler")

local consoleKickMessage = " has been kicked for using the console despite not having the permission to do so.\n"

eventHandler.OnPlayerConnect = function(pid, playerName)

    tes3mp.SetDifficulty(pid, config.difficulty)
    tes3mp.SetConsoleAllowed(pid, config.allowConsole)
    tes3mp.SetBedRestAllowed(pid, config.allowBedRest)
    tes3mp.SetWildernessRestAllowed(pid, config.allowWildernessRest)
    tes3mp.SetWaitAllowed(pid, config.allowWait)
    tes3mp.SetPhysicsFramerate(pid, config.physicsFramerate)
    tes3mp.SetEnforcedLogLevel(pid, config.enforcedLogLevel)
    tes3mp.SendSettings(pid)

    tes3mp.SetPlayerCollisionState(config.enablePlayerCollision)
    tes3mp.SetActorCollisionState(config.enableActorCollision)
    tes3mp.SetPlacedObjectCollisionState(config.enablePlacedObjectCollision)
    tes3mp.UseActorCollisionForPlacedObjects(config.useActorCollisionForPlacedObjects)

    logicHandler.SendConfigCollisionOverrides(pid, false)

    WorldInstance:LoadTime(pid, false)

    Players[pid] = Player(pid, playerName)
    Players[pid].name = playerName

    local message = logicHandler.GetChatName(pid) .. " joined the server.\n"
    tes3mp.SendMessage(pid, message, true)

    message = "Welcome " .. playerName .. "\nYou have " .. tostring(config.loginTime) ..
        " seconds to"

    if Players[pid]:HasAccount() then
        message = message .. " log in.\n"
        guiHelper.ShowLogin(pid)
    else
        message = message .. " register.\n"
        guiHelper.ShowRegister(pid)
    end

    tes3mp.SendMessage(pid, message, false)

    Players[pid].loginTimerId = tes3mp.CreateTimerEx("OnLoginTimeExpiration",
        time.seconds(config.loginTime), "i", pid)
    tes3mp.StartTimer(Players[pid].loginTimerId)
end

eventHandler.OnPlayerDisconnect = function(pid)

    if Players[pid] ~= nil then

        Players[pid]:DeleteSummons()

        -- Was this player confiscating from someone? If so, clear that
        if Players[pid].confiscationTargetName ~= nil then
            local targetName = Players[pid].confiscationTargetName
            local targetPlayer = logicHandler.GetPlayerByName(targetName)
            targetPlayer:SetConfiscationState(false)
        end

        Players[pid]:SaveCell()
        Players[pid]:SaveStatsDynamic()
        tes3mp.LogMessage(enumerations.log.INFO, "Saving player " .. logicHandler.GetChatName(pid))
        Players[pid]:Save()

        -- Unload every cell for this player
        for index, loadedCellDescription in pairs(Players[pid].cellsLoaded) do
            logicHandler.UnloadCellForPlayer(pid, loadedCellDescription)
        end

        if Players[pid].data.location.regionName ~= nil then
            logicHandler.UnloadRegionForPlayer(pid, Players[pid].data.location.regionName)
        end

        Players[pid]:Destroy()
        Players[pid] = nil
    end
end

eventHandler.OnGUIAction = function(pid, idGui, data)
    data = tostring(data) -- data can be numeric, but we should convert this to string

    if idGui == guiHelper.ID.LOGIN then
        if data == nil then
            Players[pid]:Message("Incorrect password!\n")
            guiHelper.ShowLogin(pid)
            return true
        end

        Players[pid]:Load()

        -- Just in case the password from the data file is a number, make sure to turn it into a string
        if tostring(Players[pid].data.login.password) ~= data then
            Players[pid]:Message("Incorrect password!\n")
            guiHelper.ShowLogin(pid)
            return true
        end

        -- Is this player on the banlist? If so, store their new IP and ban them
        if tableHelper.containsValue(banList.playerNames, string.lower(Players[pid].accountName)) == true then
            Players[pid]:SaveIpAddress()

            Players[pid]:Message(Players[pid].accountName .. " is banned from this server.\n")
            tes3mp.BanAddress(tes3mp.GetIP(pid))
        else
            Players[pid]:FinishLogin()
            Players[pid]:Message("You have successfully logged in.\n")
        end
    elseif idGui == guiHelper.ID.REGISTER then
        if data == nil then
            Players[pid]:Message("Password can not be empty\n")
            guiHelper.ShowRegister(pid)
            return true
        end
        Players[pid]:Register(data)
        Players[pid]:Message("You have successfully registered.\nUse Y by default to chat or " ..
            "change it from your client config.\n")

    elseif idGui == config.customMenuIds.confiscate and Players[pid].confiscationTargetName ~= nil then

        local targetName = Players[pid].confiscationTargetName
        local targetPlayer = logicHandler.GetPlayerByName(targetName)

        -- Because the window's item index starts from 0 while the Lua table for
        -- inventories starts from 1, adjust the former here
        local inventoryItemIndex = data + 1
        local item = targetPlayer.data.inventory[inventoryItemIndex]

        if item ~= nil then
        
            table.insert(Players[pid].data.inventory, item)
            Players[pid]:LoadItemChanges({item}, enumerations.inventory.ADD)

            -- If the item is equipped by the target, unequip it first
            if inventoryHelper.containsItem(targetPlayer.data.equipment, item.refId, item.charge) then
                local equipmentItemIndex = inventoryHelper.getItemIndex(targetPlayer.data.equipment,
                    item.refId, item.charge)
                targetPlayer.data.equipment[equipmentItemIndex] = nil
            end

            targetPlayer.data.inventory[inventoryItemIndex] = nil
            tableHelper.cleanNils(targetPlayer.data.inventory)

            Players[pid]:Message("You've confiscated " .. item.refId .. " from " ..
                targetName .. "\n")

            if targetPlayer:IsLoggedIn() then
                targetPlayer:LoadItemChanges({item}, enumerations.inventory.REMOVE)
            end
        else
            Players[pid]:Message("Invalid item index\n")
        end

        targetPlayer:SetConfiscationState(false)
        targetPlayer:Save()

        Players[pid].confiscationTargetName = nil

    elseif idGui == config.customMenuIds.menuHelper and Players[pid].currentCustomMenu ~= nil then

        local buttonIndex = tonumber(data) + 1
        local buttonPressed = Players[pid].displayedMenuButtons[buttonIndex]

        local destination = menuHelper.GetButtonDestination(pid, buttonPressed)

        menuHelper.ProcessEffects(pid, destination.effects)
        menuHelper.DisplayMenu(pid, destination.targetMenu)

        Players[pid].previousCustomMenu = Players[pid].currentCustomMenu
        Players[pid].currentCustomMenu = destination.targetMenu
    end

    return false
end

eventHandler.OnPlayerSendMessage = function(pid, message)

    tes3mp.LogMessage(enumerations.log.INFO, logicHandler.GetChatName(pid) .. ": " .. message)

    if message:sub(1,1) == '/' then

        local command = (message:sub(2, #message)):split(" ")
        commandHandler.ProcessCommand(pid, command)
        return false -- commands should be hidden

    -- Check for chat overrides that add extra text
    elseif Players[pid]:IsServerStaff() then

        local message = color.White .. logicHandler.GetChatName(pid) .. ": " .. message .. "\n"

        if Players[pid]:IsServerOwner() then
            message = config.rankColors.serverOwner .. "[Owner] " .. message
        elseif Players[pid]:IsAdmin() then
            message = config.rankColors.admin .. "[Admin] " .. message
        elseif Players[pid]:IsModerator() then
            message = config.rankColors.moderator .. "[Mod] " .. message
        end

        tes3mp.SendMessage(pid, message, true)
        return false
    end

    return true -- default behavior, regular chat messages should not be overridden
end

eventHandler.OnPlayerDeath = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:ProcessDeath()
    end
end

eventHandler.OnDeathTimeExpiration = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:Resurrect()
    end
end

eventHandler.OnPlayerAttribute = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:SaveAttributes()
    end
end

eventHandler.OnPlayerSkill = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:SaveSkills()
    end
end

eventHandler.OnPlayerLevel = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:SaveLevel()
        Players[pid]:SaveStatsDynamic()
    end
end

eventHandler.OnPlayerShapeshift = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:SaveShapeshift()
    end
end

eventHandler.OnPlayerCellChange = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        if contentFixer.ValidateCellChange(pid) then

            local previousCellDescription = Players[pid].data.location.cell

            -- If this player is changing their region, add them to the visitors of the new
            -- region while removing them from the visitors of their old region
            if tes3mp.IsChangingRegion(pid) then
                local regionName = string.lower(tes3mp.GetRegion(pid))

                if regionName ~= "" then
                    
                    local debugMessage = logicHandler.GetChatName(pid) .. " has "
                    
                    local hasFinishedInitialTeleportation = Players[pid].hasFinishedInitialTeleportation
                    local previousCellIsStillLoaded = tableHelper.containsValue(Players[pid].cellsLoaded,
                        previousCellDescription)

                    -- It's possible we've been teleported to a cell we had already loaded when
                    -- spawning on the server, so also check whether this is the player's first
                    -- cell change since joining
                    local isTeleported = not previousCellIsStillLoaded or not hasFinishedInitialTeleportation

                    if isTeleported then
                        debugMessage = debugMessage .. "teleported"
                    else
                        debugMessage = debugMessage .. "walked"
                    end

                    debugMessage = debugMessage .. " to region " .. regionName .. "\n"
                    tes3mp.LogMessage(enumerations.log.INFO, debugMessage)

                    logicHandler.LoadRegionForPlayer(pid, regionName, isTeleported)
                end

                local previousRegionName = Players[pid].data.location.regionName

                if previousRegionName ~= nil and previousRegionName ~= regionName then
                    logicHandler.UnloadRegionForPlayer(pid, previousRegionName)
                end

                -- Exchange generated records with the other players who have this cell loaded
                local currentCellDescription = tes3mp.GetCell(pid)
                logicHandler.ExchangeGeneratedRecords(pid, LoadedCells[currentCellDescription].visitors)

                Players[pid].data.location.regionName = regionName
                Players[pid].hasFinishedInitialTeleportation = true
            end

            Players[pid]:SaveCell()
            Players[pid]:SaveStatsDynamic()
            tes3mp.LogMessage(enumerations.log.INFO, "Saving player " .. logicHandler.GetChatName(pid))
            Players[pid]:Save()

            if config.shareMapExploration == true then
                WorldInstance:SaveMapExploration(pid)
            end
        else
            Players[pid].data.location.posX = tes3mp.GetPreviousCellPosX(pid)
            Players[pid].data.location.posY = tes3mp.GetPreviousCellPosY(pid)
            Players[pid].data.location.posZ = tes3mp.GetPreviousCellPosZ(pid)
            Players[pid]:LoadCell()
        end
    end
end

eventHandler.OnPlayerEndCharGen = function(pid)
    if Players[pid] ~= nil then
        Players[pid]:EndCharGen()
    end
end

eventHandler.OnPlayerEquipment = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:SaveEquipment()
    end
end

eventHandler.OnPlayerInventory = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:SaveInventory()
    end
end

eventHandler.OnPlayerSpellbook = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:SaveSpellbook()
    end
end

eventHandler.OnPlayerQuickKeys = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:SaveQuickKeys()
    end
end

eventHandler.OnPlayerJournal = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        if config.shareJournal == true then
            WorldInstance:SaveJournal(pid)

            -- Send this PlayerJournal packet to other players (sendToOthersPlayers is true),
            -- but skip sending it to the player we got it from (skipAttachedPlayer is true)
            tes3mp.SendJournalChanges(pid, true, true)
        else
            Players[pid]:SaveJournal()
        end
    end
end

eventHandler.OnPlayerFaction = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        local action = tes3mp.GetFactionChangesAction(pid)

        if action == enumerations.faction.RANK then
            if config.shareFactionRanks == true then

                WorldInstance:SaveFactionRanks(pid)
                -- Send this PlayerFaction packet to other players (sendToOthersPlayers is true),
                -- but skip sending it to the player we got it from (skipAttachedPlayer is true)
                tes3mp.SendFactionChanges(pid, true, true)
            else
                Players[pid]:SaveFactionRanks()
            end
        elseif action == enumerations.faction.EXPULSION then
            if config.shareFactionExpulsion == true then

                WorldInstance:SaveFactionExpulsion(pid)
                -- As above, send this to everyone other than the original sender
                tes3mp.SendFactionChanges(pid, true, true)
            else
                Players[pid]:SaveFactionExpulsion()
            end
        elseif action == enumerations.faction.REPUTATION then
            if config.shareFactionReputation == true then
                WorldInstance:SaveFactionReputation(pid)

                -- As above, send this to everyone other than the original sender
                tes3mp.SendFactionChanges(pid, true, true)
            else
                Players[pid]:SaveFactionReputation()
            end
        end
    end
end

eventHandler.OnPlayerTopic = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        if config.shareTopics == true then

            WorldInstance:SaveTopics(pid)
            -- Send this PlayerTopic packet to other players (sendToOthersPlayers is true),
            -- but skip sending it to the player we got it from (skipAttachedPlayer is true)
            tes3mp.SendTopicChanges(pid, true, true)
        else
            Players[pid]:SaveTopics()
        end
    end
end

eventHandler.OnPlayerBounty = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        if config.shareBounty == true then
            WorldInstance:SaveBounty(pid)

            -- Bounty packets are special in that they are always sent
            -- to all players, but only affect their target player on
            -- any given client
            --
            -- To set the same bounty for each LocalPlayer, we need
            -- to separately set each player as the target and
            -- send the packet
            local bountyValue = tes3mp.GetBounty(pid)

            for playerIndex, player in pairs(Players) do
                if player.pid ~= pid then
                    tes3mp.SetBounty(player.pid, bountyValue)
                    tes3mp.SendBounty(player.pid)
                end
            end
        else
            Players[pid]:SaveBounty()
        end
    end
end

eventHandler.OnPlayerReputation = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        if config.shareReputation == true then

            WorldInstance:SaveReputation(pid)
            -- Send this PlayerReputation packet to other players (sendToOthersPlayers is true),
            -- but skip sending it to the player we got it from (skipAttachedPlayer is true)
            tes3mp.SendReputation(pid, true, true)
        else
            Players[pid]:SaveReputation()
        end
    end
end

eventHandler.OnPlayerBook = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        Players[pid]:AddBooks()
    end
end

eventHandler.OnPlayerItemUse = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        local itemRefId = tes3mp.GetUsedItemRefId(pid)
        tes3mp.LogMessage(enumerations.log.INFO, logicHandler.GetChatName(pid) .. " used inventory item " .. itemRefId)

        -- Unilateral use of items is disabled on clients, so we need to send
        -- this packet back to the player before they can use the item
        tes3mp.SendItemUse(pid)
    end
end

eventHandler.OnPlayerMiscellaneous = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        local changeType = tes3mp.GetMiscellaneousChangeType(pid)

        if changeType == enumerations.miscellaneous.MARK_LOCATION then
            Players[pid]:SaveMarkLocation()
        elseif changeType == enumerations.miscellaneous.SELECTED_SPELL then
            Players[pid]:SaveSelectedSpell()
        end
    end
end

eventHandler.OnCellLoad = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        logicHandler.LoadCellForPlayer(pid, cellDescription)
    else
        tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: invalid player " .. pid ..
            " loaded cell " .. cellDescription)
    end
end

eventHandler.OnCellUnload = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        logicHandler.UnloadCellForPlayer(pid, cellDescription)
    end
end

eventHandler.OnCellDeletion = function(cellDescription)
    logicHandler.UnloadCell(cellDescription)
end

eventHandler.OnActorList = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        if LoadedCells[cellDescription] ~= nil then
            LoadedCells[cellDescription]:SaveActorList(pid)
        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent ActorList for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnActorEquipment = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        if LoadedCells[cellDescription] ~= nil then
            LoadedCells[cellDescription]:SaveActorEquipment(pid)
        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent ActorEquipment for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnActorAI = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        if LoadedCells[cellDescription] ~= nil then

            tes3mp.ReadReceivedActorList()
            tes3mp.CopyReceivedActorListToStore()

            -- Actor AI packages are currently enabled unilaterally on the client
            -- that has sent them, so we only need to send them to other players,
            -- and can skip the original sender
            -- i.e. sendToOtherVisitors is true and skipAttachedPlayer is true
            tes3mp.SendActorAI(true, true)
        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent ActorAI for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnActorDeath = function(pid, cellDescription)
    if LoadedCells[cellDescription] ~= nil then
        LoadedCells[cellDescription]:SaveActorDeath(pid)
    else
        tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
            " sent ActorDeath for unloaded " .. cellDescription)
    end
end

eventHandler.OnActorCellChange = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        if LoadedCells[cellDescription] ~= nil then
            LoadedCells[cellDescription]:SaveActorCellChanges(pid)
        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent ActorCellChange for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnObjectActivate = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        if LoadedCells[cellDescription] ~= nil then
            
            tes3mp.ReadReceivedObjectList()

            -- Add your own logic here to prevent objects from being activated in certain places,
            -- or to make specific things happen in certain situations, such as when players
            -- are activated by other players
            local isValid = true

            for index = 0, tes3mp.GetObjectListSize() - 1 do

                local debugMessage = "- "
                local isObjectPlayer = tes3mp.IsObjectPlayer(index)
                local objectPid, objectRefId, objectUniqueIndex

                if isObjectPlayer then
                    objectPid = tes3mp.GetObjectPid(index)
                    debugMessage = debugMessage .. logicHandler.GetChatName(objectPid)
                else
                    objectRefId = tes3mp.GetObjectRefId(index)
                    objectUniqueIndex = tes3mp.GetObjectRefNum(index) .. "-" .. tes3mp.GetObjectMpNum(index)
                    debugMessage = debugMessage .. objectRefId .. " " .. objectUniqueIndex
                end

                debugMessage = debugMessage .. " has been activated by "

                local doesObjectHaveActivatingPlayer = tes3mp.DoesObjectHavePlayerActivating(index)
                local activatingPid, activatingRefId, activatingUniqueIndex

                if doesObjectHaveActivatingPlayer then
                    activatingPid = tes3mp.GetObjectActivatingPid(index)
                    debugMessage = debugMessage .. logicHandler.GetChatName(activatingPid)

                    if tes3mp.GetSneakState(activatingPid) then
                        debugMessage = debugMessage .. " while sneaking"
                    end

                    local drawState = tes3mp.GetDrawState(activatingPid)

                    if drawState == 1 then
                        debugMessage = debugMessage .. " with their weapon drawn"
                    elseif drawState == 2 then
                        debugMessage = debugMessage .. " with their casting hands out"
                    end
                else
                    activatingRefId = tes3mp.GetObjectActivatingRefId(index)
                    activatingUniqueIndex = tes3mp.GetObjectActivatingRefNum(index) ..
                        "-" .. tes3mp.GetObjectActivatingMpNum(index)
                    debugMessage = debugMessage .. activatingRefId .. " " .. activatingUniqueIndex
                end

                tes3mp.LogAppend(enumerations.log.INFO, debugMessage)
            end

            -- Set isValid to false in the loop above if you want to override the default activation
            -- associated with this packet
            if isValid then
                tes3mp.CopyReceivedObjectListToStore()
                -- Objects can't be activated clientside without the server's approval, so we send
                -- the packet back to the player who sent it, but we avoid sending it to other
                -- players because OpenMW barely has any code for handling activations not from
                -- the local player
                -- i.e. sendToOtherPlayers is false and skipAttachedPlayer is false
                tes3mp.SendObjectActivate(false, false)
            end

        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent ObjectActivate for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnObjectPlace = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        tes3mp.ReadReceivedObjectList()
        local packetOrigin = tes3mp.GetObjectListOrigin()
        tes3mp.LogAppend(enumerations.log.INFO, "- packetOrigin was " ..
            tableHelper.getIndexByPattern(enumerations.packetOrigin, packetOrigin))

        if logicHandler.IsPacketFromConsole(packetOrigin) and not logicHandler.IsPlayerAllowedConsole(pid) then
            tes3mp.Kick(pid)
            tes3mp.SendMessage(pid, logicHandler.GetChatName(pid) .. consoleKickMessage, true)
            return
        end

        if LoadedCells[cellDescription] ~= nil then

            -- Iterate through the objects in the ObjectPlace packet and only sync and save them
            -- if all their refIds are valid
            local isValid = true
            local rejectedObjects = {}

            for index = 0, tes3mp.GetObjectListSize() - 1 do

                local refId = tes3mp.GetObjectRefId(index)
                local uniqueIndex = tes3mp.GetObjectRefNum(index) .. "-" .. tes3mp.GetObjectMpNum(index)

                if tableHelper.containsValue(config.disallowedCreateRefIds, refId) then
                    table.insert(rejectedObjects, refId .. " " .. uniqueIndex)
                    isValid = false
                end
            end

            if isValid then
                LoadedCells[cellDescription]:SaveObjectsPlaced(pid)

                tes3mp.CopyReceivedObjectListToStore()
                -- Objects can't be placed clientside without the server's approval, so we send
                -- the packet to other players and also back to the player who sent it,
                -- i.e. sendToOtherPlayers is true and skipAttachedPlayer is false
                tes3mp.SendObjectPlace(true, false)
            else
                tes3mp.LogMessage(enumerations.log.INFO, "Rejected ObjectPlace from " .. logicHandler.GetChatName(pid) ..
                    " about " .. tableHelper.concatenateArrayValues(rejectedObjects, 1, ", "))
            end
        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent ObjectPlace for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnObjectSpawn = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        tes3mp.ReadReceivedObjectList()
        local packetOrigin = tes3mp.GetObjectListOrigin()
        tes3mp.LogAppend(enumerations.log.INFO, "- packetOrigin was " ..
            tableHelper.getIndexByPattern(enumerations.packetOrigin, packetOrigin))

        if logicHandler.IsPacketFromConsole(packetOrigin) and not logicHandler.IsPlayerAllowedConsole(pid) then
            tes3mp.Kick(pid)
            tes3mp.SendMessage(pid, logicHandler.GetChatName(pid) .. consoleKickMessage, true)
            return
        end

        if LoadedCells[cellDescription] ~= nil then

            -- Iterate through the objects in the ObjectSpawn packet and only sync and save them
            -- if all their refIds are valid
            local isValid = true
            local rejectedObjects = {}

            for index = 0, tes3mp.GetObjectListSize() - 1 do

                local refId = tes3mp.GetObjectRefId(index)
                local uniqueIndex = tes3mp.GetObjectRefNum(index) .. "-" .. tes3mp.GetObjectMpNum(index)

                if tableHelper.containsValue(config.disallowedCreateRefIds, refId) then
                    table.insert(rejectedObjects, refId .. " " .. uniqueIndex)
                    isValid = false
                end
            end

            if isValid then
                LoadedCells[cellDescription]:SaveObjectsSpawned(pid)

                tes3mp.CopyReceivedObjectListToStore()
                -- Objects can't be spawned clientside without the server's approval, so we send
                -- the packet to other players and also back to the player who sent it,
                -- i.e. sendToOtherPlayers is true and skipAttachedPlayer is false
                tes3mp.SendObjectSpawn(true, false)
            else
                tes3mp.LogMessage(enumerations.log.INFO, "Rejected ObjectSpawn from " .. logicHandler.GetChatName(pid) ..
                    " about " .. tableHelper.concatenateArrayValues(rejectedObjects, 1, ", "))
            end
        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent ObjectSpawn for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnObjectDelete = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        tes3mp.ReadReceivedObjectList()
        local packetOrigin = tes3mp.GetObjectListOrigin()
        tes3mp.LogAppend(enumerations.log.INFO, "- packetOrigin was " ..
            tableHelper.getIndexByPattern(enumerations.packetOrigin, packetOrigin))

        if logicHandler.IsPacketFromConsole(packetOrigin) and not logicHandler.IsPlayerAllowedConsole(pid) then
            tes3mp.Kick(pid)
            tes3mp.SendMessage(pid, logicHandler.GetChatName(pid) .. consoleKickMessage, true)
            return
        end

        if LoadedCells[cellDescription] ~= nil then

            -- Iterate through the objects in the ObjectDelete packet and only sync and save them
            -- if all their refIds are valid
            local isValid = true
            local rejectedObjects = {}
            local unusableContainerUniqueIndexes = LoadedCells[cellDescription].unusableContainerUniqueIndexes

            for index = 0, tes3mp.GetObjectListSize() - 1 do

                local refId = tes3mp.GetObjectRefId(index)
                local uniqueIndex = tes3mp.GetObjectRefNum(index) .. "-" .. tes3mp.GetObjectMpNum(index)

                if tableHelper.containsValue(config.disallowedDeleteRefIds, refId) or
                    tableHelper.containsValue(unusableContainerUniqueIndexes, uniqueIndex) then
                    table.insert(rejectedObjects, refId .. " " .. uniqueIndex)
                    isValid = false
                end
            end

            if isValid then
                LoadedCells[cellDescription]:SaveObjectsDeleted(pid)

                tes3mp.CopyReceivedObjectListToStore()
                -- Objects can sometimes be deleted clientside without the server's approval and
                -- sometimes not, but we should always send ObjectDelete packets back to the sender
                -- for the sake of the latter situations
                -- i.e. sendToOtherPlayers is true and skipAttachedPlayer is false
                tes3mp.SendObjectDelete(true, false)

            else
                tes3mp.LogMessage(enumerations.log.INFO, "Rejected ObjectDelete from " .. logicHandler.GetChatName(pid) ..
                    " about " .. tableHelper.concatenateArrayValues(rejectedObjects, 1, ", "))
            end

        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent ObjectDelete for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnObjectLock = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        tes3mp.ReadReceivedObjectList()
        local packetOrigin = tes3mp.GetObjectListOrigin()
        tes3mp.LogAppend(enumerations.log.INFO, "- packetOrigin was " ..
            tableHelper.getIndexByPattern(enumerations.packetOrigin, packetOrigin))

        if logicHandler.IsPacketFromConsole(packetOrigin) and not logicHandler.IsPlayerAllowedConsole(pid) then
            tes3mp.Kick(pid)
            tes3mp.SendMessage(pid, logicHandler.GetChatName(pid) .. consoleKickMessage, true)
            return
        end

        local isCellLoaded = LoadedCells[cellDescription] ~= nil

        if not isCellLoaded and logicHandler.DoesPacketOriginRequireLoadedCell(packetOrigin) then
            tes3mp.LogMessage(enumerations.log.WARN, "Invalid ObjectLock: " .. logicHandler.GetChatName(pid) ..
                " used impossible packetOrigin for unloaded " .. cellDescription)
            return
        end

        -- Iterate through the objects in the ObjectLock packet and only sync and save them
        -- if all their refIds are valid
        local isValid = true
        local rejectedObjects = {}

        for index = 0, tes3mp.GetObjectListSize() - 1 do

            local refId = tes3mp.GetObjectRefId(index)
            local uniqueIndex = tes3mp.GetObjectRefNum(index) .. "-" .. tes3mp.GetObjectMpNum(index)

            if tableHelper.containsValue(config.disallowedLockRefIds, refId) then
                table.insert(rejectedObjects, refId .. " " .. uniqueIndex)
                isValid = false
            end
        end

        if isValid then
            local useTemporaryLoad = false

            if not isCellLoaded then
                logicHandler.LoadCell(cellDescription)
                useTemporaryLoad = true
            end

            LoadedCells[cellDescription]:SaveObjectsLocked(pid)

            if useTemporaryLoad then
                logicHandler.UnloadCell(cellDescription)
            end

            tes3mp.CopyReceivedObjectListToStore()
            -- Objects can't be locked/unlocked clientside without the server's approval,
            -- so we send the packet to other players and also back to the player who sent it,
            -- i.e. sendToOtherPlayers is true and skipAttachedPlayer is false
            tes3mp.SendObjectLock(true, false)
        else
            tes3mp.LogMessage(enumerations.log.INFO, "Rejected ObjectLock from " .. logicHandler.GetChatName(pid) ..
                " about " .. tableHelper.concatenateArrayValues(rejectedObjects, 1, ", "))
        end
    else
        tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
            " sent ObjectLock for unloaded " .. cellDescription)
    end
end

eventHandler.OnObjectTrap = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        tes3mp.ReadReceivedObjectList()
        local packetOrigin = tes3mp.GetObjectListOrigin()
        tes3mp.LogAppend(enumerations.log.INFO, "- packetOrigin was " ..
            tableHelper.getIndexByPattern(enumerations.packetOrigin, packetOrigin))

        if logicHandler.IsPacketFromConsole(packetOrigin) and not logicHandler.IsPlayerAllowedConsole(pid) then
            tes3mp.Kick(pid)
            tes3mp.SendMessage(pid, logicHandler.GetChatName(pid) .. consoleKickMessage, true)
            return
        end

        if LoadedCells[cellDescription] ~= nil then

            -- Iterate through the objects in the ObjectTrap packet and only sync and save them
            -- if all their refIds are valid
            local isValid = true
            local rejectedObjects = {}

            for index = 0, tes3mp.GetObjectListSize() - 1 do

                local refId = tes3mp.GetObjectRefId(index)
                local uniqueIndex = tes3mp.GetObjectRefNum(index) .. "-" .. tes3mp.GetObjectMpNum(index)

                if tableHelper.containsValue(config.disallowedTrapRefIds, refId) then
                    table.insert(rejectedObjects, refId .. " " .. uniqueIndex)
                    isValid = false
                end
            end

            if isValid then
                LoadedCells[cellDescription]:SaveObjectTrapsTriggered(pid)

                tes3mp.CopyReceivedObjectListToStore()
                -- Objects can't be untrapped clientside without the server's approval, so we send
                -- the packet to other players and also back to the player who sent it,
                -- i.e. sendToOtherPlayers is true and skipAttachedPlayer is false
                tes3mp.SendObjectTrap(true, false)
            else
                tes3mp.LogMessage(enumerations.log.INFO, "Rejected ObjectTrap from " .. logicHandler.GetChatName(pid) ..
                    " about " .. tableHelper.concatenateArrayValues(rejectedObjects, 1, ", "))
            end

        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent ObjectTrap for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnObjectScale = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        tes3mp.ReadReceivedObjectList()
        local packetOrigin = tes3mp.GetObjectListOrigin()
        tes3mp.LogAppend(enumerations.log.INFO, "- packetOrigin was " ..
            tableHelper.getIndexByPattern(enumerations.packetOrigin, packetOrigin))

        if logicHandler.IsPacketFromConsole(packetOrigin) and not logicHandler.IsPlayerAllowedConsole(pid) then
            tes3mp.Kick(pid)
            tes3mp.SendMessage(pid, logicHandler.GetChatName(pid) .. consoleKickMessage, true)
            return
        end

        if LoadedCells[cellDescription] ~= nil then

            -- Iterate through the objects in the ObjectScaled packet and only sync and save them
            -- if all their refIds are valid
            local isValid = true
            local rejectedObjects = {}

            for index = 0, tes3mp.GetObjectListSize() - 1 do

                local refId = tes3mp.GetObjectRefId(index)
                local uniqueIndex = tes3mp.GetObjectRefNum(index) .. "-" .. tes3mp.GetObjectMpNum(index)
                local scale = tes3mp.GetObjectScale(index)

                if scale >= config.maximumObjectScale then
                    table.insert(rejectedObjects, refId .. " " .. uniqueIndex)
                    isValid = false
                end
            end

            if isValid then
                LoadedCells[cellDescription]:SaveObjectsScaled(pid)

                tes3mp.CopyReceivedObjectListToStore()
                -- Objects can't be scaled clientside without the server's approval, so we send
                -- the packet to other players and also back to the player who sent it,
                -- i.e. sendToOtherPlayers is true and skipAttachedPlayer is false
                tes3mp.SendObjectScale(true, false)
            else
                tes3mp.LogMessage(enumerations.log.INFO, "Rejected ObjectScale from " .. logicHandler.GetChatName(pid) ..
                    " about " .. tableHelper.concatenateArrayValues(rejectedObjects, 1, ", "))
            end

        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent ObjectScale for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnObjectState = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        tes3mp.ReadReceivedObjectList()
        local packetOrigin = tes3mp.GetObjectListOrigin()
        tes3mp.LogAppend(enumerations.log.INFO, "- packetOrigin was " ..
            tableHelper.getIndexByPattern(enumerations.packetOrigin, packetOrigin))

        if logicHandler.IsPacketFromConsole(packetOrigin) and not logicHandler.IsPlayerAllowedConsole(pid) then
            tes3mp.Kick(pid)
            tes3mp.SendMessage(pid, logicHandler.GetChatName(pid) .. consoleKickMessage, true)
            return
        end

        local isCellLoaded = LoadedCells[cellDescription] ~= nil

        if not isCellLoaded and logicHandler.DoesPacketOriginRequireLoadedCell(packetOrigin) then
            tes3mp.LogMessage(enumerations.log.WARN, "Invalid ObjectState: " .. logicHandler.GetChatName(pid) ..
                " used impossible packetOrigin for unloaded " .. cellDescription)
            return
        end

        -- Iterate through the objects in the ObjectState packet and only sync and save them
        -- if all their refIds are valid
        local isValid = true
        local rejectedObjects = {}

        for index = 0, tes3mp.GetObjectListSize() - 1 do

            local refId = tes3mp.GetObjectRefId(index)
            local uniqueIndex = tes3mp.GetObjectRefNum(index) .. "-" .. tes3mp.GetObjectMpNum(index)

            if tableHelper.containsValue(config.disallowedStateRefIds, refId) then
                table.insert(rejectedObjects, refId .. " " .. uniqueIndex)
                isValid = false
            end
        end

        if isValid then
            local useTemporaryLoad = false

            if not isCellLoaded then
                logicHandler.LoadCell(cellDescription)
                useTemporaryLoad = true
            end

            LoadedCells[cellDescription]:SaveObjectStates(pid)

            if useTemporaryLoad then
                logicHandler.UnloadCell(cellDescription)
            end

            tes3mp.CopyReceivedObjectListToStore()
            -- Objects can't be enabled or disabled clientside without the server's approval,
            -- so we send the packet to other players and also back to the player who sent it,
            -- i.e. sendToOtherPlayers is true and skipAttachedPlayer is false
            tes3mp.SendObjectState(true, false)
        else
            tes3mp.LogMessage(enumerations.log.INFO, "Rejected ObjectState from " .. logicHandler.GetChatName(pid) ..
                " about " .. tableHelper.concatenateArrayValues(rejectedObjects, 1, ", "))
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnDoorState = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        if LoadedCells[cellDescription] ~= nil then
            LoadedCells[cellDescription]:SaveDoorStates(pid)
        else
            tes3mp.LogMessage(enumerations.log.WARN, "Undefined behavior: " .. logicHandler.GetChatName(pid) ..
                " sent DoorState for unloaded " .. cellDescription)
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnContainer = function(pid, cellDescription)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        tes3mp.ReadReceivedObjectList()
        local packetOrigin = tes3mp.GetObjectListOrigin()
        tes3mp.LogAppend(enumerations.log.INFO, "- packetOrigin was " ..
            tableHelper.getIndexByPattern(enumerations.packetOrigin, packetOrigin))

        if logicHandler.IsPacketFromConsole(packetOrigin) and not logicHandler.IsPlayerAllowedConsole(pid) then
            tes3mp.Kick(pid)
            tes3mp.SendMessage(pid, logicHandler.GetChatName(pid) .. consoleKickMessage, true)
            return
        end

        local isCellLoaded = LoadedCells[cellDescription] ~= nil

        if not isCellLoaded and logicHandler.DoesPacketOriginRequireLoadedCell(packetOrigin) then
            tes3mp.LogMessage(enumerations.log.WARN, "Invalid Container: " .. logicHandler.GetChatName(pid) ..
                " used impossible packetOrigin for unloaded " .. cellDescription)
            return
        end

        -- Iterate through the objects in the Container packet and only sync and save them
        -- if all their refIds are valid
        local isValid = true
        local rejectedObjects = {}
        local unusableContainerUniqueIndexes = {}

        if isCellLoaded then
            unusableContainerUniqueIndexes = LoadedCells[cellDescription].unusableContainerUniqueIndexes
        end

        local subAction = tes3mp.GetObjectListContainerSubAction()

        for index = 0, tes3mp.GetObjectListSize() - 1 do

            local refId = tes3mp.GetObjectRefId(index)
            local uniqueIndex = tes3mp.GetObjectRefNum(index) .. "-" .. tes3mp.GetObjectMpNum(index)

            if tableHelper.containsValue(unusableContainerUniqueIndexes, uniqueIndex) then
                
                if subAction == enumerations.containerSub.REPLY_TO_REQUEST then
                    tableHelper.removeValue(unusableContainerUniqueIndexes, uniqueIndex)
                    tes3mp.LogMessage(enumerations.log.INFO, "Making container " .. uniqueIndex ..
                        " usable as a result of request reply")
                else
                    table.insert(rejectedObjects, refId .. " " .. uniqueIndex)
                    isValid = false

                    Players[pid]:Message("That container is currently unusable for synchronization reasons.\n")
                end
            end
        end

        if isValid then
            local useTemporaryLoad = false

            if not isCellLoaded then
                logicHandler.LoadCell(cellDescription)
                useTemporaryLoad = true
            end

            -- Don't sync this packet here; BaseCell():SaveContainers will have to
            -- deal with it
            LoadedCells[cellDescription]:SaveContainers(pid)

            if useTemporaryLoad then
                logicHandler.UnloadCell(cellDescription)
            end
        else
            tes3mp.LogMessage(enumerations.log.INFO, "Rejected Container from " .. logicHandler.GetChatName(pid) ..
                " about " .. tableHelper.concatenateArrayValues(rejectedObjects, 1, ", "))
        end
    else
        tes3mp.Kick(pid)
    end
end

eventHandler.OnVideoPlay = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        tes3mp.ReadReceivedObjectList()
        local packetOrigin = tes3mp.GetObjectListOrigin()
        tes3mp.LogAppend(enumerations.log.INFO, "- packetOrigin was " ..
            tableHelper.getIndexByPattern(enumerations.packetOrigin, packetOrigin))

        if logicHandler.IsPacketFromConsole(packetOrigin) and not logicHandler.IsPlayerAllowedConsole(pid) then
            tes3mp.Kick(pid)
            tes3mp.SendMessage(pid, logicHandler.GetChatName(pid) .. consoleKickMessage, true)
            return
        end

        if config.shareVideos == true then
            tes3mp.LogMessage(enumerations.log.WARN, "Sharing VideoPlay from " .. logicHandler.GetChatName(pid))

            for i = 0, tes3mp.GetObjectListSize() - 1 do
                local videoFilename = tes3mp.GetVideoFilename(i)
                tes3mp.LogAppend(enumerations.log.WARN, "- videoFilename " .. videoFilename)
            end

            tes3mp.CopyReceivedObjectListToStore()

            -- Send this VideoPlay packet to other players (sendToOthersPlayers is true),
            -- but skip sending it to the player we got it from (skipAttachedPlayer is true)
            tes3mp.SendVideoPlay(true, true)
        end
    end
end

eventHandler.OnRecordDynamic = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        tes3mp.ReadReceivedWorldstate()
        
        local recordNumericalType = tes3mp.GetRecordType(pid)

        -- Iterate through the records in the RecordDynamic packet and only sync and save them
        -- if all their names are allowed
        local isValid = true
        local rejectedRecords = {}

        if recordNumericalType ~= enumerations.recordType.ENCHANTMENT then
            local recordCount = tes3mp.GetRecordCount(pid)

            for recordIndex = 0, recordCount - 1 do
                local recordName = tes3mp.GetRecordName(recordIndex)

                if not logicHandler.IsNameAllowed(recordName) then
                    table.insert(rejectedRecords, recordName)
                    isValid = false

                    Players[pid]:Message("You are not allowed to create a record called " .. recordName .. "\n")
                end
            end
        end

        if not isValid then
            tes3mp.LogMessage(enumerations.log.INFO, "Rejected RecordDynamic from " .. logicHandler.GetChatName(pid) ..
                " about " .. tableHelper.concatenateArrayValues(rejectedRecords, 1, ", "))
            return
        end

        local storeType = string.lower(tableHelper.getIndexByPattern(enumerations.recordType, recordNumericalType))
        local recordStore = RecordStores[storeType]
        local isEnchantable, recordAdditions

        if recordStore == nil then
            tes3mp.LogMessage(enumerations.log.WARN, "Rejected RecordDynamic for invalid record store of type " ..
                recordNumericalType)
            return
        else
            isEnchantable = tableHelper.containsValue(config.enchantableRecordTypes, storeType)
        end

        if storeType == "spell" then
            recordAdditions = recordStore:SaveGeneratedSpells(pid)
        elseif storeType == "potion" then
            recordAdditions = recordStore:SaveGeneratedPotions(pid)
        elseif storeType == "enchantment" then
            recordAdditions = recordStore:SaveGeneratedEnchantments(pid)
        elseif isEnchantable then
            recordAdditions = recordStore:SaveGeneratedEnchantedItems(pid)
        end

        tes3mp.CopyReceivedWorldstateToStore()

        -- Iterate through the record additions and make any necessary adjustments
        for _, recordAddition in pairs(recordAdditions) do

            -- Set the server-generated ids of the records in our stored copy of the
            -- RecordsDynamic packet before we send it to the players
            tes3mp.SetRecordIdByIndex(recordAddition.index, recordAddition.id)

            if storeType == "enchantment" then
                -- We need to store this enchantment's original client-generated id
                -- on this player so we can match it with its server-generated correct
                -- id once the player sends the record of the enchanted item they've
                -- used it on
                Players[pid].unresolvedEnchantments[recordAddition.clientsideId] = recordAddition.id
            elseif isEnchantable then
                -- Set the server-generated id for this enchanted item's enchantment
                tes3mp.SetRecordEnchantmentIdByIndex(recordAddition.index, recordAddition.enchantmentId)
            end

            -- This record will be sent to everyone on the server just after this loop,
            -- so track it as having already been received by players
            for _, player in pairs(Players) do
                table.insert(player.generatedRecordsReceived, recordAddition.id)
            end
        end

        -- Send this RecordDynamic packet to other players (sendToOthersPlayers is true),
        -- and also send it to the player we got it from (skipAttachedPlayer is false)
        tes3mp.SendRecordDynamic(pid, true, false)
    
        -- Add the final spell to the player's spellbook
        if storeType == "spell" then

            tes3mp.ClearSpellbookChanges(pid)
            tes3mp.SetSpellbookChangesAction(pid, enumerations.spellbook.ADD)
            
            for _, recordAddition in pairs(recordAdditions) do
                table.insert(Players[pid].data.spellbook, recordAddition.id)
                tes3mp.AddSpell(pid, recordAddition.id)

                Players[pid]:AddLinkToRecord(storeType, recordAddition.id)
            end

            recordStore:Save()
            Players[pid]:Save()
            tes3mp.SendSpellbookChanges(pid)

        -- Add the final items to the player's inventory
        elseif storeType == "potion" or isEnchantable then

            local enchantmentStore

            if isEnchantable then enchantmentStore = RecordStores["enchantment"] end

            local itemArray = {}
            
            for _, recordAddition in pairs(recordAdditions) do
                local item = { refId = recordAddition.id, count = 1, charge = -1, enchantmentCharge = -1 }
                table.insert(Players[pid].data.inventory, item)
                table.insert(itemArray, item)

                Players[pid]:AddLinkToRecord(storeType, recordAddition.id)

                -- If this is an enchantable item record, add a link to it from its associated
                -- enchantment record
                if isEnchantable then
                    enchantmentStore:AddLinkToRecord(recordAddition.enchantmentId,
                        recordAddition.id, storeType)
                end
            end

            if isEnchantable then enchantmentStore:Save() end

            recordStore:Save()
            Players[pid]:Save()
            Players[pid]:LoadItemChanges(itemArray, enumerations.inventory.ADD)
        end
    end
end

eventHandler.OnWorldKillCount = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        WorldInstance:SaveKills(pid)
    end
end

eventHandler.OnWorldMap = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
        WorldInstance:SaveMapTiles(pid)

        if config.shareMapExploration == true then
            tes3mp.CopyReceivedWorldstateToStore()

            -- Send this WorldMap packet to other players (sendToOthersPlayers is true),
            -- but skip sending it to the player we got it from (skipAttachedPlayer is true)
            tes3mp.SendWorldMap(pid, true, true)
        end
    end
end

eventHandler.OnWorldWeather = function(pid)
    if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then

        tes3mp.ReadReceivedWorldstate()

        local regionName = string.lower(tes3mp.GetWeatherRegion())

        -- Track current weather in each region
        if WorldInstance.storedRegions[regionName] ~= nil then
            WorldInstance:SaveRegionWeather(regionName)
        end

        -- Go through the other players on the server and send them this weather update
        for _, otherPlayer in pairs(Players) do

            local otherPid = otherPlayer.pid

            -- Ignore the player we got the weather from
            if otherPid ~= pid then

                -- If this player has been marked as requiring a force weather update for
                -- this region, provide them with one
                if WorldInstance:IsForcedWeatherUpdatePid(otherPid, regionName) then
                    WorldInstance:LoadRegionWeather(regionName, otherPid, false, true)
                    WorldInstance:RemoveForcedWeatherUpdatePid(otherPid, regionName)
                else
                    WorldInstance:LoadRegionWeather(regionName, otherPid, false, false)
                end
            end
        end
    end
end

eventHandler.OnMpNumIncrement = function(currentMpNum)
    WorldInstance:SetCurrentMpNum(currentMpNum)
end

eventHandler.OnObjectLoopTimeExpiration = function(loopIndex)
    if ObjectLoops[loopIndex] ~= nil then

        local loop = ObjectLoops[loopIndex]
        local pid = loop.targetPid
        local loopEnded = false

        if Players[pid] ~= nil and Players[pid]:IsLoggedIn() and
            Players[pid].accountName == loop.targetName then
        
            if loop.packetType == "place" or loop.packetType == "spawn" then
                logicHandler.CreateObjectAtPlayer(pid, loop.refId, loop.packetType)
            elseif loop.packetType == "console" then
                logicHandler.RunConsoleCommandOnPlayer(pid, loop.consoleCommand)
            end

            loop.count = loop.count - 1

            if loop.count > 0 then
                ObjectLoops[loopIndex] = loop
                tes3mp.RestartTimer(loop.timerId, loop.interval)
            else
                loopEnded = true
            end
        else
            loopEnded = true
        end

        if loopEnded == true then
            ObjectLoops[loopIndex] = nil
        end
    end
end

return eventHandler
