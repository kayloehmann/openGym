#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

CAP_PLUGIN(NativeWorkoutPlugin, "NativeWorkout",
           CAP_PLUGIN_METHOD(present, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(update, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(dismiss, CAPPluginReturnPromise);
)
