import http from 'http'
import express from 'express'
import cors from 'cors'
import morgan from 'morgan'
import bodyParser from 'body-parser'
import middleware from './middleware'
import routes from './routes'
import HomeConnectManager from './home-connect'
import config from '../config/config.json'

let app = express()
app.server = http.createServer(app)

// logger
app.use(morgan('dev'))

// 3rd party middleware
app.use(cors({
	exposedHeaders: config.corsHeaders
}))

app.use(bodyParser.json({
	limit : config.bodyLimit
}))

const manager = new HomeConnectManager({
	dataStorageDir: config.dataStorageDir,
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

export default app
