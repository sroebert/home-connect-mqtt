import mqtt from 'mqtt'

/**
 * @typedef {Object} MQTTManagerConfig
 * @property {string} url
 * @property {?string} username
 * @property {?string} password
 */

export default class MQTTManager {

  // ===
  // Initialize
  // ===
  
  /**
   * @param {MQTTManagerConfig} config 
   */
  constructor(config) {
    this.config = config
    this._topicPrefix = 'home-connect'
    this._subscribedAppliances = new Set()

    this._connectPromise = new Promise((resolve) => {
      this._mqtt = mqtt.connect(config.url, {
        username: config.username,
        password: config.password
      })
      this._mqtt.on('connect', () => {
        resolve()
        this._subscribe()
      })
      this._mqtt.on('error', (err) => {
        console.log(`mqtt error: ${err}`)
      })
    })
  }

  // ===
  // Publish
  // ===

  async publishAppliances(appliances) {
    this._appliances = appliances
    this._subscribeForAppliances()

    await this._connectPromise

    for (const [, appliance] of Object.entries(appliances)) {
      this.publishAppliance(appliance)
    }
  }

  publishAppliance(appliance) {
    if (!this._appliances) {
      this._appliances = {}
    }

    this._appliances[appliance.haId] = appliance
    this._subscribeForAppliances()

    this._publishMessages(appliance, [
      {
        topic: 'connected',
        payload: appliance.connected ? 'true' : 'false'
      },
      {
        topic: 'info',
        payload: JSON.stringify({
          id: appliance.haId,
          name: appliance.name,
          brand: appliance.brand,
          type: appliance.type
        })
      },
    ])

    this.publishApplianceUpdate(appliance, [
      'status',
      'settings',
      'programs.active',
      'programs.selected'
    ])
  }

  publishApplianceUpdate(appliance, updates) {
    if (!this._appliances) {
      this._appliances = {}
    }
    this._appliances[appliance.haId] = appliance

    const messages = updates.map(update => this._messageForUpdate(appliance, update))
    this._publishMessages(appliance, messages)
  }

  // ===
  // Subscribe
  // ===

  _subscribe() {
    this._mqtt.on('message', (topic, messageBuffer) => {
      const topicParts = topic.split('/')
      topicParts.shift()

      const message = messageBuffer.toString()

      if (topicParts.length == 1 && topicParts[0] == 'command') {
        switch (message) {
        case 'announce':
          this._announce()
          break

        default:
          console.log(`Unknown global command received: ${message}`)
        } 
      } else if (topicParts.length == 2 && topicParts[1] == 'command') {
        const haId = topicParts[0]
        const appliance = this._appliances[haId]
        if (!appliance) {
          return
        }

        this._handleApplianceCommand(appliance, message)
      }
    })

    this._mqtt.subscribe(`${this._topicPrefix}/command`, { qos: 2 })
    this._subscribeForAppliances()
  }

  async _subscribeForAppliances() {
    if (!this._appliances) {
      return
    }

    await this._connectPromise
    for (const [, appliance] of Object.entries(this._appliances)) {
      if (!this._subscribedAppliances.has(appliance.haId)) {
        this._subscribedAppliances.add(appliance.haId)
        this._mqtt.subscribe(`${this._topicPrefix}/${appliance.haId}/command`, { qos: 2 })
      }
    }
  }

  _announce() {
    if (!this._appliances) {
      return
    }

    this.publishAppliances(this._appliances)
  }

  _handleApplianceCommand(appliance, message) {
    let json = null
    try {
      json = JSON.parse(message)
    } catch (err) {
      console.log(`Invalid appliance command received for ${appliance.haId}: ${message}`)
      return
    }

    if (this.onApplianceCommand) {
      this.onApplianceCommand(appliance, json)
    }
  }

  // ===
  // Utils
  // ===

  _messageForUpdate(appliance, update) {
    if (update == 'status') {
      return {
        topic: 'status',
        payload: this._convertPayload(appliance.status)
      }
    } else if (update == 'settings') {
      return {
        topic: 'settings',
        payload: this._convertPayload(appliance.settings)
      }
    } else if (update == 'programs.active') {
      return {
        topic: 'programs/active',
        payload: this._convertPayload(appliance.programs.active)
      }
    } else if (update == 'programs.selected') {
      return {
        topic: 'programs/selected',
        payload: this._convertPayload(appliance.programs.selected)
      }
    } else if (update.startsWith('events.')) {
      const key = update.substr(7)
      const value = appliance.events[key]
      return {
        topic: `events/${key}`,
        payload: this._convertPayload(value),
        retain: value == 'present'
      }
    }
  }

  _convertPayload(payload) {
    return payload ? JSON.stringify(payload) : JSON.stringify(null)
  }

  _publishMessages(appliance, messages) {
    const topicPrefix = `${this._topicPrefix}/${appliance.haId}`
    messages.forEach(message => {
      this._mqtt.publish(`${topicPrefix}/${message.topic}`, message.payload, {
        qos: 2,
        retain: message.retain
      })
    })
  }
}
