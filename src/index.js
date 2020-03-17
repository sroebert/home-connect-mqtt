import http from 'http'
import express from 'express'
import cors from 'cors'
import morgan from 'morgan'
import bodyParser from 'body-parser'
import middleware from './middleware'
import routes from './routes'
import HomeConnectManager from './home-connect'
import fs from 'fs'

let app = express()
app.server = http.createServer(app)
app.use(morgan('dev'))

fs.readFile(process.env.CONFIG_FILE || 'data/config.json', (err, data) => {
	if (err) {
		console.log(`Failed to load config json: ${err}`)
		return
	}

	let config = null
	try {
		config = JSON.parse(data)
	} catch (jsonErr) {
		console.log(`Failed to parse config json: ${jsonErr}`)
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
	})
	manager.start()
	
	app.use(middleware({ config }))
	app.use('/', routes({ config, manager }))
	
	app.server.listen(process.env.PORT || config.port, () => {
		console.log(`Started on port ${app.server.address().port}`)
	});
})

export default app
