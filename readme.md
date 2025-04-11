A garmin watch datafield that shows a breadcrumb trail. For watches that do not support breadcrumb navigation out of the box.

companion app https://github.com/pauljohnston2025/breadcrumb-mobile.git
Can be used without the companion app, but will only show current track. 
Use the companion app to add a route that you can follow.

Intended for use with round watches, but will work on others (might not look the best though).  
Some watches/devices with touch support will be able switch between elevation and track view during activity.

Donations are always welcome, but not required: paypal.me/pauljohnston2025

Settings:

Garmin has an issue with array settings where they cannot be modified by the connect iq app it appears to be a known issue, but unlikely to be solved. Per route settings should be edited from the wath only, attempts to edit them from the connect iq settings page will likely break until garmin fix the issue.

Garmin also do not seem to show any of the descriptions anymore, so here they are:

Most settings should be prety obvious, or can be playe with to find out what they do. The complicated ones are.

Scale: Pixels per meter 0 to use the distance specified by `Meters Around User` in the `Zoom At Pace` menu

Zoom At Pace:
Map will automatically zoom when moving or stopped, can be disabled by manually settings scale

Meters Around User: how far to render around the user when zoomed in
Speed: How fast the user needs to be moving in order to trigger zoom changes. You could set this to a really high value if you do not want zoom to occur. and then configure `Meters Around User` to the desired value.


Maps:
Choose these values wisely. Too big = crash, too small = crash or slow performance. 

Tile Url: Should be 'http://127.0.0.1:8080' for companion app or template eg. 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png'. 
Tile Size: Tile size should be a multiple of 256 for best results. The tile size in pixels loaded from the companion app or other source. Should be 256 if using a template. There are known issues with setting it smaller (performance being a big one), but it does work on some devices.
Tile Layer Max: The maximum tile layer that can be fetched.
Tile Layer Min: The maximum tile layer that can be fetched.
Tile Cache Padding: The maximum tiles to grab around the user 0 means no more than the screen size. 1 will give you one extra layer of tiles as a buffer (so they are pre loaded when we move into that area)
Tile Cache Size: The number of tiles to store locally in memory.
Max Pending Web Requests: The macx number of tile fetch requests we can have quued ready to be sent.
Disable Maps After X Failures: Maps wil be auto matically disabled if this many tile fetch requests fail. 0 - unlimited
Fixed Latitude: The latitude to render (must also set longitude)
Fixed Longitude: The longitude to render (must also set latitude)

Set both latitude and longitude to 0 to disable fixed position and use the current location.

Best Guess for map settings:
Tile Cache Size if using zoom at pace: 2*<Tile Cache Size without zoom at pace>
Tile Cache Size if NOT using zoom at pace: ((2 * ceil(<screen size>/<tile size>)) + 2 * <tile cache padding>)^2 
Max Pending Web Requests: Tile Cache Size
eg. on venu2s is scale is set to `0.075` it uses approximetely 10*10 tiles to fill the screen, this means the tile cache would need to be set to at least 100 (at 64 you can see the tiles loading and unloading)
The math above is worst case, if you pick a better fixed scale or `Meters Around User` then the tile cache size can be significantly reduced (by at least half). Layer min/max could also be used to specify a fixed layer and further reduce the need for tiless in memory (since we can zoom in and make a single tile cover the screen). All these settings are here so users can configure their own memory requirements for the best battery life and stability. Suggest settings the scale to one that you like, and then reducing the tile cache size untill black aras appear to find the limit.

Colours: Should be set to a valid hex code AARRGGBB not all are required eg. FF00 will render as green

Target User: Hikers, backpackers, cyclists, trail runners, and outdoor enthusiasts seeking a flexible navigation tool for their Garmin watches. Especially valuable for users with Garmin devices that do not have built-in map support. Suitable for both on- and off-grid exploration, with customizable maps and route following capabilities.

Key Features:

Breadcrumb Trail Navigation: Displays a route as a breadcrumb trail overlaid on a map, allowing users to easily follow the intended path. Brings map-based navigation to Garmin devices that do not have native map support.  
Map Tile Loading (Online): Supports any tile server that uses EPSG:3857 image tiles.  
Map Tile Loading (Offline): Loads pre-cached tile data from the companion app.  
Off-Track Alerts (needs to be enbaled in garmins setting menu, see below): Notifies the user when they deviate from the planned route.  
Elevation Overview: Shows an elevation profile of the route, allowing users to anticipate upcoming climbs and descents.  
Routing (companion app required): Users can import routes from Google Maps or GPX files using the companion app.  
Customizable Settings: Fully customizable via the watch or Connect IQ settings. No companion app required for basic functionality.  
Breadcrumb-Only Mode: (Optional) A simplified display mode showing only the breadcrumb trail, without the underlying map tiles, for increased battery life on devices with limited screen resolution or memory.  

note: Map support is disabled by default, but can be turned on in app settings, this is because map tile loading is memory intensive and may cause crashes on some devices.

Companion app:
The companion app is available on my github: https://github.com/pauljohnston2025/breadcrumb-mobile.git  
While all settings can be configured directly on the watch or through Connect IQ settings, the companion app unlocks powerful features such as offline map support via Bluetooth transfer and route loading. Currently, the companion app is only available on Android, but contributions from iOS developers are highly welcomed to expand platform support and bring these functionalities to a wider audience.


This is a datafield, not a full fledged app, it runs in the context of native activity.  

The datafield is expected to be used to cover the full available area of a round watchface.  
It will still work with non-round devices or partial layouts, but the full feature set of the ui will not be possible due to the limited space.  

To add datafield to a native app:
* Open the app (eg. running), you do not have to start the activity, just open it.
* Long press to open settings (or use the touchscreen to press settings)
* Navigate to Data Screens
* Select screen
* Choose layout - recommended full screen layout
* Edit data fields - choose the 'BreadCrumbDataField' from the 'ConnectIQ Fields' menu

For the venu range: https://support.garmin.com/en-AU/?faq=gyywAozBuAAGlvfzvR9VZ8&identifier=707572&searchQuery=data%20field&tab=topics  
A more thorough explaination for a different app can be found at: https://support.garmin.com/en-AU/?faq=3HkHX1wT6U7TeNB7YHfiT7&identifier=707572&searchQuery=data%20field&tab=topics

It is much easier to configure the settings from the ConnectIQ - But it is possble to use the on device settings modification.

To edit settings from on device (on venu series):
* Open the app (eg. running). DO NOT start the activity, you can only edit before activity start.
* Use touch screen to slide up settings. DO NOT long press, as that only gives you access to the run settings (layouts etc.), not our settings
* You should now see a menu 'ConnectIQ Fields'
* From here we can select 'BreadCrumbDataField' and modify our settings

Settings Can now also be now be edited through the alerts menu (on venu series):
* Open the app (eg. running). Start the activity.
* Long press the bottom button to open run settings
* Click Alerts / Add new
* Scroll down to 'Connect IQ'
* From here we can select 'BreadCrumbDataField' and modify our settings
* Opening the settings again can be found in the alerts tab (click 'BreadCrumbDataField' then modify settings)

For online routing, the tile server url can be set to something like:

Open Topo Map:  
Terain: https://a.tile.opentopomap.org/{z}/{x}/{y}.png  

OpenStreetMap will not work as a templated tile server on the watch because makeImageRequest does not allow headers to be sent. OpenStreetMap requires that the User-Agent header be sent or it will respond with 403. Use the tile server hosted on the companion app if you wish to use OpenStreetMap.   
~~OpenStreetMap:~~  
~~Standard: https://tile.openstreetmap.org/{z}/{x}/{y}.png~~

Google:  
Hybrid: https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}  
Satellite: https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}  
Road: https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}  

Esri:  
View available tiles at https://server.arcgisonline.com/arcgis/rest/services/  

World Imagery (Satellite): https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}  
World Street Map: https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}  
World Topo Map: https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}  
World Hillshade Base: https://server.arcgisonline.com/arcgis/rest/services/Elevation/World_Hillshade/MapServer/tile/{z}/{y}/{x}  

Carto:  
Voyager: https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png  
Dark Matter: https://a.basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png  
Light All: https://a.basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png  