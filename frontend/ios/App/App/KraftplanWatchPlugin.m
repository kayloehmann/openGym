#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

CAP_PLUGIN(KraftplanWatchPlugin, "KraftplanWatch",
           CAP_PLUGIN_METHOD(publish, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(pending, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(clear, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(ack, CAPPluginReturnPromise);
)
