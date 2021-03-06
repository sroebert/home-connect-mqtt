import axios from 'axios'
import qs from 'qs'
import { URL } from 'url'
import storage from 'node-persist'
import https from 'https'
import EventSource from 'eventsource'
import winston from 'winston'

const API_DOMAIN = 'api.home-connect.com'
// const API_DOMAIN = 'simulator.home-connect.com'

/**
 * @typedef {import('express').Request} Request
 * @typedef {import('axios').AxiosInstance} AxiosInstance
 * @typedef {import('axios').AxiosResponse} AxiosResponse
 */

/**
 * @typedef {Object} APIManagerConfig
 * @property {string} tokenStorageDir
 * @property {string} clientId
 * @property {string} clientSecret
 * @property {string} redirectUri
 */

export default class APIManager {

  // ===
  // Initialize
  // ===

  /**
   * @param {APIManagerConfig} config 
   */
  constructor(config, logger = winston) {
    this.config = config
    this.logger = logger

    this._httpsAgent = new https.Agent({
      keepAlive: true,
      maxSockets: 1,
      timeout: 15000
    })
    this._authorizeAxios = this._createAuthorizeAxios()
    this._apiAxios = this._createAPIAxios()
  }

  /**
   * @returns {AxiosInstance}
   */
  _createAuthorizeAxios() {
    const instance = axios.create({
      httpsAgent: this._httpsAgent,
      baseURL:  `https://${API_DOMAIN}/security/oauth/`,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      timeout: 10000,
      transformRequest: [(data) => {
        return qs.stringify(data)
      }]
    })
    return instance
  }

  /**
   * @returns {AxiosInstance}
   */
  _createAPIAxios() {
    const instance = axios.create({
      httpsAgent: this._httpsAgent,
      baseURL:  `https://${API_DOMAIN}/api/`,
      headers: {
        'Content-Type': 'application/json',
      },
      timeout: 10000
    })
    this._setupTokenHandling(instance)
    return instance
  }

  /**
   * @param {AxiosInstance} axiosInstance
   */
  _setupTokenHandling(axiosInstance) {
    axiosInstance.interceptors.request.use(
      async config => {
        const accessToken = await this._getAccessToken()
        config.headers['Authorization'] = `Bearer ${accessToken}`
        return config
      },
      error => {
        return Promise.reject(error)
      }
    )
    axiosInstance.interceptors.response.use(
      response => {
        return response
      },
      error => {
        if (error.response && error.response.status == 401) {
          this.logger.error('Received 401 while communicating with API, refreshing access token')
          this._waitForRefreshToken(this._token).catch(() => {
            // Nothing to do
          })
        }
        return Promise.reject(error)
      }
    )
  }

  // ===
  // Token
  // ===

  async _getStorage() {
    if (this._storage) {
      return this._storage
    }

    const apiStorage = storage.create({
      dir: this.config.tokenStorageDir
    })
    await apiStorage.init()

    this._storage = apiStorage
    return apiStorage
  }

  async _getAccessToken() {
    if (!this._token) {
      const storage = await this._getStorage()
      this._token = await storage.getItem('token') || {}
    }

    if (!this._token || !this._token.refresh_token) {
      throw new Error('Not authorized')
    }

    if (!this._token.access_token ||
      !this._token.expires_at ||
      this._token.expires_at - Date.now() < 60 * 60 * 1000) {
      
      const token = await this._waitForRefreshToken(this._token)
      return token.access_token
    }

    return this._token.access_token
  }

  async _waitForRefreshToken(token) {
    if (this._refreshTokenPromise) {
      return await this._refreshTokenPromise
    }

    this._refreshTokenPromise = this._refreshToken(token)
    
    const result = await this._refreshTokenPromise
    this._refreshTokenPromise = null

    return result
  }

  async _refreshToken(token) {
    this.logger.warn('Refreshing access token')

    try {
      const response = await this._authorizeAxios.post('token', {
        grant_type: 'refresh_token',
        refresh_token: token.refresh_token,
        client_secret: this.config.clientSecret
      })
      this.logger.warn(`Refreshed access token, expires in ${token.expires_in} seconds`)

      await this._storeToken(response.data)
      return response.data

    } catch (err) {
      this.logger.error(`Failed to refresh access token: ${err.message}`)
      throw err
    }
  }

  async _storeToken(token) {
    token.expires_at = Date.now() + 1000 * token.expires_in
    this._token = token

    const storage = await this._getStorage()
    await storage.setItem('token', token)
  }

  // ===
  // Authorization
  // ===

  async isAuthorized() {
    try {
      await this._getAccessToken()
      return true
    } catch (err) {
      return false
    }
  }

  createAuthorizationUrl() {
    const authorizeUrl = new URL(`${this._authorizeAxios.defaults.baseURL}authorize`);
    authorizeUrl.searchParams.set('client_id', this.config.clientId)
    authorizeUrl.searchParams.set('redirect_uri', this.config.redirectUri)
    authorizeUrl.searchParams.set('response_type', 'code')
    authorizeUrl.searchParams.set('scope', 'IdentifyAppliance Monitor Control Settings')
    return authorizeUrl
  }

  /**
   * @param {Request} req 
   */
  async authorizeFromCallbackRequest(req) {
    const code = req.query.code
    if (!code) {
      throw new Error('Missing authorization code')
    }

    const response = await this._authorizeAxios.post('token', {
      grant_type: 'authorization_code',
      code: code,
      client_id: this.config.clientId,
      client_secret: this.config.clientSecret,
      redirect_uri: this.config.redirectUri
    })

    await this._storeToken(response.data)
  }

  // ===
  // Requests
  // ===

  /**
   * @param {string} path
   * @returns {Promise<AxiosResponse>}
   */
  async get(path) {
    return await this._apiAxios.get(path)
  }

  /**
   * @param {string} path
   * @param {?any} data
   * @returns {Promise<AxiosResponse>}
   */
  async put(path, data = null) {
    return await this._apiAxios.put(path, data)
  }

  /**
   * @param {string} path
   * @returns {Promise<AxiosResponse>}
   */
  async delete(path) {
    return await this._apiAxios.delete(path)
  }

  /**
   * @param {string} path
   * @returns {Promise<EventSource>}
   */
  async getEventSource(path) {
    const accessToken = await this._getAccessToken()

    const url = `${this._apiAxios.defaults.baseURL}${path}`
    return new EventSource(url, {
      headers: {
        'Authorization': `Bearer ${accessToken}`
      }
    })
  }
}