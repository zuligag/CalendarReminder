//
//  ContentView.swift
//  MyDay
//
//  Created by Derek Denny-Brown on 1/14/22.
//

import EventKit
import SwiftUI
import UserNotifications

struct ContentView: View {
    let cal = Today()
    @State var events:[EventToday]
    @State private var timer = Timer.publish(
        every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading)
        {
            HStack {
                Button("Load") {
                    events = cal.getEvents()
                }
            }
            ForEach(events) { event in
                HStack() {
                    Text(String(format: "%02D:%02D-%02D:%02D",
                                event.start/60, event.start%60,
                                event.end/60, event.end%60))
                        .font(Font.system(.body, design: .monospaced))
                    Text(event.title)
                }
            }
        }
        .padding()
        .onReceive(timer) { _ in
            events = cal.getEvents()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(events:[EventToday(start:9,end:10,title:"Sample"), EventToday(start:10,end:11,title:"abc")])
    }
}

extension TimeInterval {

    var seconds: Int {
        return Int(self.rounded())
    }

    var minutes: Int {
        return seconds / 60
    }
}

struct EventToday: Identifiable {
    let id: String
    let start: Int
    let end: Int
    let title: String
    
    init(start:Int, end:Int, title:String) {
        self.id = UUID().uuidString
        self.start = start*60
        self.end = end*60
        self.title = title
    }

    init(e:EKEvent) {
        id = e.calendarItemIdentifier
        let startOfDay = Calendar.current.startOfDay(for: Date())
        start = max(startOfDay.distance(to: e.startDate).minutes, 0)
        end = min(startOfDay.distance(to: e.endDate).minutes, 24*60)
        title = e.title
    }
    static func fromEvent(e:EKEvent) -> EventToday {
        EventToday(e: e)
    }
}

class Today: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let store = EKEventStore()
    var initialized = false;
    var error:String? = nil
    var events:[EventToday] = []

    override init() {
    }
    
    func getEvents() -> [EventToday] {
        if !initialized {
            // Request access to reminders.
            store.requestAccess(to: .event) { granted, err in
                // Handle the response to the request.
                if (!granted) {
                    self.error = err?.localizedDescription
                    print("EventStore access NOT Granted!")
                    print(err?.localizedDescription as Any)
                }
            }
            
            center.requestAuthorization(options: [.alert, .sound]) { (granted, err) in
                if !granted {
                    self.error = err?.localizedDescription
                    print("UserNotificationCenter access NOT Granted!")
                    print(err?.localizedDescription as Any)
                }
            }
            center.delegate = self

            initialized = true
        }

        if (error == nil) {
            let cal = Calendar.current
            let sDate = cal.startOfDay(for: Date())
            let eDate = cal.date(byAdding: .day, value: 1, to: sDate) ?? sDate
            let pred = store.predicateForEvents(
                withStart: sDate, end: eDate,
                calendars: store.calendars(for: .event))
            let updatedEvents = store.events(matching: pred)
                .compactMap(EventToday.fromEvent)
                .sorted(by: {a, b in a.start < b.start})
            // build a map of id->event
            let updatedEventsMap = updatedEvents.reduce(into: [String: EventToday]()) {
                $0[$1.id] = $1
            }
            let prevEventIds = Set(events.map { e in e.id })
            let newEventIds = Set(updatedEvents.map { e in e.id })
            let commonIds = prevEventIds.intersection(newEventIds)
            // remove notifications for any event that when away
            let removalIds = Array(prevEventIds.subtracting(commonIds))
            for id in removalIds {
                print("remove notification for \(id)")
            }
            center.removePendingNotificationRequests(withIdentifiers: removalIds)
            // add new notification for new events
            for id in newEventIds.subtracting(commonIds) {
                let event = updatedEventsMap[id]
                if event != nil {
                    print("add notification for \(id) : \(event!.title)")
                    addNotification(event:event!)
                }
            }
            self.events = updatedEvents
        }
        return events
    }

    func addNotification(event: EventToday) {
        var dateComponents = DateComponents()
        dateComponents.hour = event.start/60
        dateComponents.minute = event.start%60
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents, repeats: true)
        
        let content = UNMutableNotificationContent()
        content.title = event.title
//        content.body = "The early bird catches the worm, but the second mouse gets the cheese."
        content.categoryIdentifier = "alarm"
//        content.userInfo = ["customData": "fizzbuzz"]
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        center.removeAllPendingNotificationRequests()
        center.add(request)
        print("notification scheduled")
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Swift.Void) {
        completionHandler( [.badge, .sound])
    }

}


