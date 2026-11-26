#if DEBUG
import Foundation
import CoreData
import SwiftData

/// Debug builds only. Creates every record type Tracker uses in the iCloud *development* database, so the schema
/// can then be deployed to production in the CloudKit Console (TestFlight and App Store builds use production).
/// Runs only when the app is launched with `-initCloudKitSchema YES`, on a throwaway store, so real data isn't touched.
enum CloudKitSchema {
    static func initializeIfAsked(types: [any PersistentModel.Type], container: String) {
        guard UserDefaults.standard.bool(forKey: "initCloudKitSchema") else { return }
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: types) else {
            print("CloudKitSchema: couldn't build the model")
            return
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "schema-init.store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: container)
        description.shouldAddStoreAsynchronously = false
        let cloud = NSPersistentCloudKitContainer(name: "SchemaInit", managedObjectModel: model)
        cloud.persistentStoreDescriptions = [description]
        cloud.loadPersistentStores { _, error in
            if let error { print("CloudKitSchema: store error \(error)") }
        }
        do {
            try cloud.initializeCloudKitSchema()
            print("CloudKitSchema: done")
        } catch {
            print("CloudKitSchema: failed \(error)")
        }
        for store in cloud.persistentStoreCoordinator.persistentStores {
            try? cloud.persistentStoreCoordinator.remove(store)
        }
    }
}
#endif
