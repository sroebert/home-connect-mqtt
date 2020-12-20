import APIManager from './api-manager'
import MQTTManager from './mqtt-manager'
import schedule from 'node-schedule'
import { camelCase } from 'camel-case'
import command_mapping from './command-mapping'
import winston from 'winston'

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
  constructor(config, logger = winston) {
    this.config = config
    this.logger = logger

    this._isRunning = false
    this._apiManager = new APIManager({
      tokenStorageDir: `${config.dataStorageDir}/token`,
      clientId: config.clientId,
      clientSecret: config.clientSecret,
      redirectUri: config.redirectUri
    }, logger)
    this._mqttManager = new MQTTManager({
      url: config.mqttUrl,
      username: config.mqttUsername,
      password: config.mqttPassword
    }, logger)
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
    this.logger.info('Starting HomeConnectManager')

    this._apiManager.isAuthorized().then(isAuthorized => {
      if (isAuthorized) {
        this._run()
      } else {
        this.logger.error('Not authorized')
      }
    })
  }

  _run() {
    if (this._isRunning) {
      return
    }

    this._isRunning = true
    this._startRetrievingAppliances()
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

  _startRetrievingAppliances() {
    this.logger.info('Retrieving appliances...')

    this._retrieveAppliances()
      .then(() => {
        this.logger.info('Found appliances:')
        Object.keys(this._appliances).forEach(id => {
          this.logger.warn(`${this._appliances[id].name} (${id})`)
        })

        this._startMonitoringAppliances()
      })
      .catch(err => {
        this.logger.error(`Failed to retrieve appliances: ${err.message}`)

        this.logger.info('Scheduling to retrieve appliances again in 30 seconds')
        schedule.scheduleJob(Date.now() + 30 * 1000, () => {
          this._startRetrievingAppliances()
        })
      })
  }

  async _retrieveAppliances() {
    const appliances = await this._getAppliances()
    const appliancesWithState = await Promise.all(appliances.map(async(appliance) => {
      return await this._updateApplianceWithState(appliance)
    }))

    this._appliances = {}
    appliancesWithState.forEach(appliance => {
      this._appliances[appliance.haId] = appliance
    })

    this._mqttManager.publishAppliances(this._appliances)
  }

  _startMonitoringAppliances() {
    this.logger.info('Monitoring appliances...')

    this._monitorAppliances().catch(err => {
      this.logger.error(`Failed to monitor appliances: ${err.message}`)

      this.logger.info('Scheduling to monitor appliances again in 30 seconds')
      schedule.scheduleJob(Date.now() + 30 * 1000, () => {
        this._startMonitoringAppliances()
      })
    })
  }

  async _monitorAppliances() {
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

  async _listenForEvents() {
    this._stopListeningForEvents()

    this._eventSource = await this._apiManager.getEventSource('homeappliances/events')

    const keepAliveTime = 60 * 1000
    this.keepAliveLogCount = 0

    const events = ['KEEP-ALIVE', 'STATUS', 'EVENT', 'NOTIFY', 'CONNECTED', 'DISCONNECTED']
    events.forEach(eventName => {
      this._eventSource.addEventListener(eventName, event => {
        this._scheduleKeepAlive(keepAliveTime)
        this._handleEvent(event)
      })
    })

    this._eventSource.onerror = (err) => {
      this.logger.error(`Error in the event source: ${err.message}`)
      this._startMonitoringAppliances()
    }

    this._scheduleKeepAlive(keepAliveTime)
  }

  _scheduleKeepAlive(keepAliveTime) {
    if (this._keepAliveJob) {
      this._keepAliveJob.cancel()
      this._keepAliveJob = null
    }

    this._keepAliveJob = schedule.scheduleJob(Date.now() + keepAliveTime, () => {
      this.logger.error('Failed to keep event source alive, restarting...')
      this._startMonitoringAppliances()
    })
  }

  _stopListeningForEvents() {
    if (this._keepAliveJob) {
      this._keepAliveJob.cancel()
      this._keepAliveJob = null
    }

    if (this._eventSource) {
      this._eventSource.onerror = () => {}
      this._eventSource.close()
      this._eventSource = null
    }
  }

  // ===
  // Commands
  // ===

  async _onApplianceCommand(appliance, command) {
    for (const [key, value] of Object.entries(command)) {
      const entry = command_mapping[key]
      if (!entry) {
        this.logger.error(`Received unknown command for ${appliance.name}: ${key}`)
        continue
      }

      const valueEntry = entry.values[value]
      if (!valueEntry) {
        this.logger.error(`Received unknown value for ${appliance.name} and command ${key}: ${value}`)
        continue
      }

      let apiValue = valueEntry
      if (valueEntry.constructor == Object) {
        apiValue = valueEntry[appliance.type]
      }

      try {
        this.logger.info(`Performing command ${key} for ${appliance.name}`, { value: apiValue })

        await this._apiManager.put(`homeappliances/${appliance.haId}/${entry.path}/${entry.key}`, {
          data: {
              key: entry.key,
              value: apiValue
          }
        })

        // Update locally
        this._handleApplianceUpdateItems(appliance, [
          {
            key: entry.key,
            value: apiValue,
            uri: `/api/homeappliances/${appliance.haId}/${entry.path}/${entry.key}`
          }
        ])

      } catch (err) {
        this.logger.error(`Failed to perform command ${key} for ${appliance.name}: ${err.message}`)

        // Since the call failed, update the appliance, making sure we have up to date info in MQTT
        this._forceUpdateAppliance(appliance.haId)
      }
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

    appliance.programs = {
      active: await this._getApplianceProgram(appliance.haId, 'active'),
      selected: await this._getApplianceProgram(appliance.haId, 'selected'),
    }

    appliance.events = {}

    return appliance
  }

  async _getApplianceProgram(haId, type) {
    const reducer = (object, item) => {
      let key = this._convertKey(item.key)
      object[key] = this._convertValue(item.value)
      return object
    }

    const response = await this._apiManager.get(`homeappliances/${haId}/programs/${type}`)
      .catch(this._recoverStatus([404, 409], { data: { data: null } }))
    let program = response.data.data

    if (program) {
      let options = program.options || []
      program = {
        name: this._convertValue(program.key),
        options: options.reduce(reducer, {})
      }
    }
    return program
  }

  async _forceUpdateAppliance(haId) {
    let appliance = await this._getAppliance(haId)
    appliance = await this._updateApplianceWithState(appliance)

    this._appliances[haId] = appliance
    this._mqttManager.publishAppliance(appliance)
  }

  _handleEvent(event) {
    switch (event.type) {
      case 'KEEP-ALIVE':
        this.keepAliveLogCount += 1
        if (this.keepAliveLogCount >= 60 * 2) { // Only every two hours
          this.logger.verbose('Received keep alive')
          this.keepAliveLogCount = 0
        } else {
          this.logger.debug('Received keep alive')
        }
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
        this.logger.verbose(`Appliance ${event.lastEventId} ${event.type}, updating...`)
        this._forceUpdateAppliance(event.lastEventId).then(() =>{
          this.logger.verbose(`${event.lastEventId} updated.`)
        }).catch(() => {
          this.logger.error(`Failed to update appliance ${event.lastEventId} after ${event.type}`)
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

    this._handleApplianceUpdateItems(appliance, data.items)
  }

  _handleApplianceUpdateItems(appliance, items) {
    const uriPrefix = `/api/homeappliances/${appliance.haId}`
    let updates = new Set()

    items.forEach(item => {
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

          // Update to get all the program details
          this._forceUpdateAppliance(appliance.haId)
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

          // Update to get all the program details
          this._forceUpdateAppliance(appliance.haId)
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
      const updateArray = [...updates]
      this.logger.verbose(`${appliance.name} updated`, { 'updates': updateArray })
      this._mqttManager.publishApplianceUpdate(appliance, updateArray)
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

      this.logger.verbose(`${appliance.name} triggered event ${key}`)
    })

    if (data.items.length > 0) {
      this._mqttManager.publishApplianceUpdate(appliance, updates)
    }
  }
}
