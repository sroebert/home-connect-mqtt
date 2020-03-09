import APIManager from './api-manager'
import MQTTManager from './mqtt-manager'
import schedule from 'node-schedule'
import { camelCase } from 'camel-case'
import command_mapping from './command-mapping'

/**
 * @typedef {Object} HomeConnectManagerConfig
 * @property {string} dataStorageDir
 * @property {string} clientId
 * @property {string} clientSecret
 * @property {string} redirectUri
 * @property {string} mqttUrl
 * @property {string} mqttUsername
 * @property {string} mqttPassword
 */

export default class HomeConnectManager {
  
  // ===
  // Initialize
  // ===

  /**
   * @param {HomeConnectManagerConfig} config 
   */
  constructor(config) {
    this.config = config

    this._isRunning = false
    this._apiManager = new APIManager({
      tokenStorageDir: `${config.dataStorageDir}/token`,
      clientId: config.clientId,
      clientSecret: config.clientSecret,
      redirectUri: config.redirectUri
    })
    this._mqttManager = new MQTTManager({
      url: config.mqttUrl,
      username: config.mqttUsername,
      password: config.mqttPassword
    })
    this._mqttManager.onApplianceCommand = (appliance, command) => {
      this._onApplianceCommand(appliance, command)
    }
  }

  // ===
  // Authorization
  // ===

  async isAuthorized() {
    return this._apiManager.isAuthorized()
  }

  createAuthorizationUrl() {
    return this._apiManager.createAuthorizationUrl()
  }

  async authorizeFromCallbackRequest(req) {
    await this._apiManager.authorizeFromCallbackRequest(req)
    this._run()
  }

  // ===
  // Start
  // ===

  start() {
    this._apiManager.isAuthorized().then(isAuthorized => {
      if (isAuthorized) {
        this._run()
      } else {
        console.log('Not authorized')
      }
    })
  }

  _run() {
    if (this._isRunning) {
      return
    }

    this._isRunning = true
    this._retrieveDevices().catch(err => {
      console.log(`Failed to retrieve devices: ${err}`)

      schedule.scheduleJob(Date.now() + 5 * 60 * 1000, () => {
        this._retrieveDevices()
      })
    })
  }

  _recoverStatus(validStatus, value = null) {
    return async(err) => {
      if (!err.response) {
        throw err
      }

      if ((Array.isArray(validStatus) && validStatus.includes(err.response.status)) ||
          err.response.status == validStatus) {
        return value
      }

      throw err
    }
  }

  async _retrieveDevices() {
    const appliances = await this._getAppliances()
    const appliancesWithState = await Promise.all(appliances.map(async(appliance) => {
      return await this._updateApplianceWithState(appliance)
    }))

    this._appliances = {}
    appliancesWithState.forEach(appliance => {
      this._appliances[appliance.haId] = appliance
    })

    this._mqttManager.publishAppliances(this._appliances)
    this._startMonitoringDevices()
  }

  _startMonitoringDevices() {
    this._monitorDevices().catch(err => {
      console.log(`Failed to monitor devices: ${err}`)

      schedule.scheduleJob(Date.now() + 5 * 60 * 1000, () => {
        this._monitorDevices()
      })
    })
  }

  async _monitorDevices() {
    await this._listenForEvents()
  }

  // ===
  // API Calls
  // ===

  async _getAppliances() {
    const response = await this._apiManager.get('homeappliances')
    return response.data.data.homeappliances
  }

  async _getAppliance(haId) {
    const response = await this._apiManager.get(`homeappliances/${haId}`)
    return response.data.data
  }

  async _getApplianceStatus(haId) {
    const response = await this._apiManager.get(`homeappliances/${haId}/status`)
    return response.data.data.status
  }

  async _getApplianceSettings(haId) {
    const response = await this._apiManager.get(`homeappliances/${haId}/settings`)
    return response.data.data.settings
  }

  async _getApplianceActiveProgram(haId) {
    const response = await this._apiManager.get(`homeappliances/${haId}/programs/active`)
    return response.data.data
  }

  async _getApplianceSelectedProgram(haId) {
    const response = await this._apiManager.get(`homeappliances/${haId}/programs/selected`)
    return response.data.data
  }

  async _listenForEvents() {
    this._stopListeningForEvents()

    this._eventSource = await this._apiManager.getEventSource('homeappliances/events')

    const keepAliveTime = 60 * 1000

    const events = ['KEEP-ALIVE', 'STATUS', 'EVENT', 'NOTIFY', 'CONNECTED', 'DISCONNECTED']
    events.forEach(eventName => {
      this._eventSource.addEventListener(eventName, event => {
        this._keepAliveJob.reschedule(keepAliveTime)
        this._handleEvent(event)
      })
    })

    this._eventSource.onerror = () => {
      schedule.scheduleJob(Date.now() + 5 * 1000, () => {
        this._monitorDevices()
      })
    }

    this._keepAliveJob = schedule.scheduleJob(Date.now() + keepAliveTime, () => {
      if (this._eventSource) {
        console.log('Failed to keep alive, retrying')
        this._listenForEvents()
      }
    })
  }

  _stopListeningForEvents() {
    if (!this._eventSource) {
      return
    }

    if (this._keepAliveJob) {
      this._keepAliveJob.cancel()
      this._keepAliveJob = null
    }
    this._eventSource.close()
    this._eventSource = null
  }

  // ===
  // Commands
  // ===

  _onApplianceCommand(appliance, command) {
    for (const [key, value] of Object.entries(command)) {
      const entry = command_mapping[key]
      if (!entry) {
        console.log(`Received unknown command for appliance ${appliance.haId}: ${key}`)
        continue
      }

      const valueEntry = entry.values[value]
      if (!valueEntry) {
        console.log(`Received unknown value for appliance ${appliance.haId} and command ${key}: ${value}`)
        continue
      }

      let apiValue = valueEntry
      if (valueEntry.constructor == Object) {
        apiValue = valueEntry[appliance.type]
      }

      this._apiManager.put(`homeappliances/${appliance.haId}/${entry.path}/${entry.key}`, {
        data: {
            key: entry.key,
            value: apiValue
        }
      })
    }
  }

  // ===
  // Utils
  // ===

  _convertKey(key) {
    return camelCase(key.split('.').pop())
  }

  _convertValue(value) {
    if (typeof value === 'string' || value instanceof String) {
      value = camelCase(value.split('.').pop())
    }
    return value
  }

  async _updateApplianceWithState(appliance) {
    const reducer = (object, item) => {
      let key = this._convertKey(item.key)
      object[key] = this._convertValue(item.value)
      return object
    }

    let status = await this._getApplianceStatus(appliance.haId)
      .catch(this._recoverStatus(409))
    appliance.status = status ? status.reduce(reducer, {}) : null

    let settings = await this._getApplianceSettings(appliance.haId)
      .catch(this._recoverStatus(409))
    appliance.settings = settings ? settings.reduce(reducer, {}) : null

    let activeProgram = await this._getApplianceActiveProgram(appliance.haId)
      .catch(this._recoverStatus([404, 409]))
    if (activeProgram) {
      let options = activeProgram.options || []
      activeProgram = {
        name: this._convertValue(activeProgram.key),
        options: options.reduce(reducer, {})
      }
    }

    let selectedProgram = await this._getApplianceSelectedProgram(appliance.haId)
      .catch(this._recoverStatus([404, 409]))
    if (selectedProgram) {
      let options = selectedProgram.options || []
      selectedProgram = {
        name: this._convertValue(selectedProgram.key),
        options: options.reduce(reducer, {})
      }
    }

    appliance.programs = {
      active: activeProgram,
      selected: selectedProgram,
    }

    appliance.events = {}

    return appliance
  }

  async _forceUpdateAppliance(haId) {
    let appliance = await this._getAppliance(haId)
    appliance = await this._updateApplianceWithState(appliance)

    this._appliances[haId] = appliance
    this._mqttManager.publishAppliance(appliance)
  }

  _handleEvent(event) {
    console.log(event)
    switch (event.type) {
      case 'KEEP-ALIVE':
        break

      case 'STATUS':
      case 'NOTIFY': {
        this._insertEventItems(event)
        break
      }

      case 'EVENT':
        this._handleEventEvent(event)
        break

      case 'CONNECTED': 
      case 'DISCONNECTED': {
        this._forceUpdateAppliance(event.lastEventId).catch(() => {
          console.log(`Failed to update appliance: ${event.lastEventId}`)
        })
        break
      }

      default:
        break
    }
  }

  _insertEventItems(event)  {
    const data = JSON.parse(event.data)
    const appliance = this._appliances[data.haId]
    if (!appliance) {
      return
    }

    const uriPrefix = `/api/homeappliances/${data.haId}`
    let updates = new Set()
    
    data.items.forEach(item => {
      const key = this._convertKey(item.key)
      const value = this._convertValue(item.value)

      if (item.uri == `${uriPrefix}/status/${item.key}`) {
        appliance.status[key] = value
        updates.add('status')
      } else if (item.uri == `${uriPrefix}/settings/${item.key}`) {
        appliance.settings[key] = value
        updates.add('settings')
      } else if (item.uri == `${uriPrefix}/programs/active`) {
        if (value) {
          appliance.programs.active = appliance.programs.active || {name: "unknown", options: {}}
          appliance.programs.active.name = value
        } else {
          appliance.programs.active = null
        }
        updates.add('programs.active')
      } else if (item.uri == `${uriPrefix}/programs/active/options/${item.key}`) {
        appliance.programs.active = appliance.programs.active || {name: "unknown", options: {}}
        appliance.programs.active.options[key] = value
        updates.add('programs.active')
      } else if (item.uri == `${uriPrefix}/programs/selected`) {
        if (value) {
          appliance.programs.selected = appliance.programs.selected || {name: "unknown", options: {}}
          appliance.programs.selected.name = value
        } else {
          appliance.programs.selected = null
        }
        updates.add('programs.selected')
      } else if (item.uri == `${uriPrefix}/programs/selected/options/${item.key}`) {
        appliance.programs.selected = appliance.programs.selected || {name: "unknown", options: {}}
        appliance.programs.selected.options[key] = value
        updates.add('programs.selected')
      }
    })

    if (updates.size > 0) {
      this._mqttManager.publishApplianceUpdate(appliance, [...updates])
    }
  }

  _handleEventEvent(event)  {
    const data = JSON.parse(event.data)
    const appliance = this._appliances[data.haId]
    if (!appliance) {
      return
    }

    let updates = []
    data.items.forEach(item => {
      const key = this._convertKey(item.key)
      const value = this._convertValue(item.value)
      appliance.events[key] = value

      updates.push(`events.${key}`)
    })

    if (data.items.length > 0) {
      this._mqttManager.publishApplianceUpdate(appliance, updates)
    }
  }
}