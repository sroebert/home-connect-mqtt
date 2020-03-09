import { version } from '../../package.json'
import { Router } from 'express'

export default ({ config, manager }) => {
	let api = Router()

	// perhaps expose some API metadata at the root
	api.get('/', (req, res) => {
		res.json({ version })
	})

	api.get('/home-connect/authorize', (req, res) => {
		res.redirect(manager.createAuthorizationUrl().toString())
	})

	api.get('/home-connect/callback', async(req, res, next) => {
		try {
			await manager.authorizeFromCallbackRequest(req)
			res.set('Content-Type', 'text/html')
			res.send('<html><body>Success</body></html>')
		} catch (err) {
			next(err)
		}
	})

	return api
}
