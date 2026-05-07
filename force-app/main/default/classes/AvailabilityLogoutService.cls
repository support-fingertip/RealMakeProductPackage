/**
 * @description REST endpoint for reliable logout on tab/browser close.
 *              Called via navigator.sendBeacon() or fetch({keepalive:true})
 *              from the myAvailabilityToggle LWC, which ensures the request
 *              completes even after the page begins unloading.
 */
@RestResource(urlMapping='/availability/logout')
global with sharing class AvailabilityLogoutService {

    @HttpPost
    global static void doLogout() {
        UserAvailabilityController.logoutSession();
    }
}