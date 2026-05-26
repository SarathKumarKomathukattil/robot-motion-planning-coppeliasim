sim = require 'sim'
simOMPL = require 'simOMPL'
simIK = require 'simIK'

function getConfig()
    local retVal = {}
    for i = 1, #simJointHandles, 1 do
        retVal[i] = sim.getJointPosition(simJointHandles[i])
    end
    return retVal
end

function setConfig(config)
    for i = 1, #simJointHandles, 1 do
        sim.setJointPosition(simJointHandles[i], config[i])
    end
end

function configurationValidationCallback(config)
    local tmp = getConfig()
    setConfig(config)
    local valid = true
    if sim.checkCollision(robotCollection, obstacleCollection) ~= 0 then
        valid = false
    end
    local tipZ = sim.getObjectPosition(sim.getObject('../tip'), -1)[3]
    if tipZ < 0.01 then
        valid = false
    end
    setConfig(tmp)
    return valid
end

function sysCall_thread()
    simBase = sim.getObject('..')
    simJointHandles = {}
    useForProjection = {}
    for i = 1, 7, 1 do
        simJointHandles[i] = sim.getObject('../joint', {index = i - 1})
        useForProjection[i] = i <= 3 and 1 or 0
    end
    local simTip = sim.getObject('../tip')
    local simTarget = sim.getObject('../target')
    targets = {
        sim.getObject('/target1'),
        sim.getObject('/target2'),
        sim.getObject('/target3'),
        sim.getObject('/target4')
    }
    robotCollection = sim.createCollection()
    sim.addItemToCollection(robotCollection, sim.handle_tree, simBase, 0)
    obstacleCollection = sim.createCollection()
    sim.addItemToCollection(obstacleCollection, sim.handle_single, sim.getObject('/obstacle1'), 0)
    sim.addItemToCollection(obstacleCollection, sim.handle_single, sim.getObject('/obstacle2'), 0)
    sim.addItemToCollection(obstacleCollection, sim.handle_single, sim.getObject('/obstacle3'), 0)
    sim.addItemToCollection(obstacleCollection, sim.handle_single, sim.getObject('/obstacle4'), 0)
    ikEnv = simIK.createEnvironment()
    ikGroup = simIK.createGroup(ikEnv)
    local _, simToIkObjectMapping = simIK.addElementFromScene(
        ikEnv, ikGroup, simBase, simTip, simTarget, simIK.constraint_position
    )
    ikJointHandles = {}
    for i = 1, #simJointHandles, 1 do
        ikJointHandles[i] = simToIkObjectMapping[simJointHandles[i]]
    end
    ikTarget = simToIkObjectMapping[simTarget]
    ikBase = simToIkObjectMapping[simBase]
    local tcnt = 1
    while true do
        local pose = sim.getObjectPose(targets[tcnt], simBase)
        simIK.setObjectPose(ikEnv, ikTarget, pose, ikBase)
        local configs = simIK.findConfigs(ikEnv, ikGroup, ikJointHandles, {
            maxDist = 1.5,
            trials = 1000,
            cb = configurationValidationCallback
        })
        if #configs > 0 then
            local config = configs[1]
            local task = simOMPL.createTask('task')
            simOMPL.setAlgorithm(task, simOMPL.Algorithm.RRTConnect)
            simOMPL.setStateSpaceForJoints(task, simJointHandles, useForProjection)
            simOMPL.setCollisionPairs(task, {robotCollection, obstacleCollection})
            simOMPL.setStartState(task, getConfig())
            simOMPL.setGoalState(task, config)
            simOMPL.setup(task)
            local res, path = simOMPL.compute(task, 6, -1, 1000)
            if res and path then
                local sw = sim.setStepping(true)
                for i = 1, simOMPL.getPathStateCount(task, path) do
                    local conf = simOMPL.getPathState(task, path, i)
                    setConfig(conf)
                    sim.step()
                end
                sim.setStepping(sw)
                sim.wait(1)
            end
            simOMPL.destroyTask(task)
        end
        tcnt = tcnt + 1
        if tcnt > 4 then tcnt = 1 end
        sim.wait(1)
    end
end