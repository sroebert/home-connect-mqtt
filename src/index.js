import http from 'http'
import express from 'express'
import cors from 'cors'
import morgan from 'morgan'
import bodyParser from 'body-parser'
import middleware from './middleware'
import routes from './routes'
import HomeConnectManager from './home-connect'
import fs from 'fs'
import winston from 'winston'
import dotenv from 'dotenv'

dotenv.config({
	path: '.env.local'
})
dotenv.config()

const logger = winston.createLogger({
	level: process.env.LOG_LEVEL || 'info',
	format: winston.format.combine(
		winston.format.colorize({
			all: true
		}),
		winston.format.timestamp({
			format: 'YYYY-MM-DD HH:mm:ss'
		}),
		winston.format.printf(({ level, message, timestamp, ...meta }) => {
			var metaString = ""
			if (Object.keys(meta).length > 0) {
				metaString = ` ${JSON.stringify(meta)}`
			}

			return `${timestamp} [${level}]: ${message}${metaString}`
		}),
	),
	transports: [
		new winston.transports.Console()
	]
})

let app = express()
app.server = http.createServer(app)
app.use(morgan('dev'))

fs.readFile(process.env.CONFIG_FILE || 'data/config.json', (err, data) => {
	if (err) {
		logger.error(`Failed to load config json: {err.message}`)
		return
	}

	let config = null
	try {
		config = JSON.parse(data)
	} catch (jsonErr) {
		logger.error(`Failed to parse config json: ${jsonErr.message}`)
		return
	}

	app.use(cors({
		exposedHeaders: config.corsHeaders
	}))
	
	app.use(bodyParser.json({
		limit : config.bodyLimit
	}))
	
	const manager = new HomeConnectManager({
		dataStorageDir: process.env.DATA_DIR || './data',
		clientId: config.clientId,
		clientSecret: config.clientSecret,
		redirectUri: config.redirectUri,
		mqttUrl: config.mqttUrl,
		mqttUsername: config.mqttUsername,
		mqttPassword: config.mqttPassword
	}, logger)
	manager.start()
	
	app.use(middleware({ config }))
	app.use('/', routes({ config, manager }))
	
	app.server.listen(process.env.PORT || config.port, () => {
		logger.info(`Started listening on port ${app.server.address().port}`)
	});
})

export default app
