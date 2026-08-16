param appName string

resource app 'Microsoft.Web/sites@2023-12-01' existing = {
  name: appName
}

resource appSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: app
  name: 'appsettings'
  properties: union(app.listApplicationSettings().properties, {
    PUBLIC_API_BASE_URL: 'https://${app.properties.defaultHostName}'
    CALLBACK_URI: 'https://${app.properties.defaultHostName}/filestatus'
  })
}

output backendUrl string = 'https://${app.properties.defaultHostName}'
