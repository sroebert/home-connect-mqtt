const Keys = {
  settings: {
    powerState: 'BSH.Common.Setting.PowerState'
  }
}

const Values = {
  powerState: {
    on: 'BSH.Common.EnumType.PowerState.On',
    off: 'BSH.Common.EnumType.PowerState.Off',
    standby: 'BSH.Common.EnumType.PowerState.Standby',
    get(appliance, value) {
      if (value == 'on') {
        return Values.powerState.on
      } else {
        switch (appliance.type) {
        case 'Oven':
        case 'CoffeeMachine':
        case 'CleaningRobot':
        case 'CookProcessor':
          return Values.powerState.standby

        default:
          return Values.powerState.off
        }
      }
    }
  },
  preheat: {
    program: 'Cooking.Oven.Program.HeatingMode.PreHeating'
  }
}

export default {
  power: {
    path: `settings/${Keys.settings.powerState}`,
    isSupported(appliance, value) {
      return true
    },
    isValidValue(appliance, value) {
      return value == 'on' || value == 'off'
    },
    data(appliance, value) {
      return {
        key: Keys.settings.powerState,
        value: Values.powerState.get(appliance, value)
      }
    },
    event(appliance, value) {
      return {
        key: Keys.settings.powerState,
        value: Values.powerState.get(appliance, value),
        uri: `/api/homeappliances/${appliance.haId}/settings/${Keys.settings.powerState}`
      }
    }
  },

  preheat: {
    path: 'programs/active',
    isSupported(appliance, value) {
      return appliance.type == 'Oven'
    },
    isValidValue(appliance, value) {
      if (typeof value != 'object') {
        return false
      }
      return typeof value.temperature == "number"
    },
    data(appliance, value) {
      return {
        key: Values.preheat.program,
        options: [
          {
            key: 'Cooking.Oven.Option.SetpointTemperature',
            value: value.temperature,
            unit: '°C'
          },
          {
            key: 'BSH.Common.Option.Duration',
            value: 900,
            unit: 'seconds'
          },
          {
            key: 'Cooking.Oven.Option.FastPreHeat',
            value: value.fastPreHeat ? true : false
          }
        ]
      }
    },
    event(appliance, value) {
      return {
        key: 'BSH.Common.Root.ActiveProgram',
        value: Values.preheat.program,
        uri: `/api/homeappliances/${appliance.haId}/programs/active`
      }
    }    
  }
}