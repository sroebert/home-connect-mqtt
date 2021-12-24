# home-connect-mqtt

Swift app build on Vapor for connecting with the Home Connect API and publishing device information over MQTT. It is also possible to send commands over MQTT to turn on/off devices and start preheating an oven.

## Setup

The app can be run using Docker.

### Environment Variables

The following environment variables are required to run the app. To get a client id and secret, an app has to be setup at the Home Connect developer page: https://developer.home-connect.com. The redirect url has to point to your running instance with path `home-connect/callback` (e.g. `http://127.0.0.1:8080/home-connect/callback`).

The MQTT username and password are optional.

```
HOME_CONNECT_CLIENT_ID=client_id
HOME_CONNECT_CLIENT_SECRET=client_secret
HOME_CONNECT_REDIRECT_URL=redirect_url

MQTT_URL=mqtt://host
MQTT_USERNAME=username
MQTT_PASSWORD=password
```

### Authorization

After starting the app for the first time, it will first have to be authorized. To do this go to the following url on your running instance: `http://127.0.0.1:8080/home-connect/authorize`. Once authorized, it will start publishing through MQTT.


## Commands

### Announce

To make the app re-publish all device states, send `announce` to the topic `home-connect/command`.

### Power

To turn an appliance `on` or `off`, send `{"power": "on"}` or `{"power": "off"}` to the topic `home-connect/DEVICE_ID/command`.

### Preheat

To preheat an oven, send `{"preheat": {"temperature": 180, "fastPreHeat": true}}` to the topic `home-connect/DEVICE_ID/command`.
