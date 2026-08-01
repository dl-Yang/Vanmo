#if os(iOS)
import BackgroundTasks
import Foundation
import SwiftData
import VanmoCore

enum ScanBackgroundTask {
    static let identifier = "com.vanmo.app.media-scan"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(processingTask)
        }
    }

    static func scheduleIfNeeded() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            VanmoLogger.library.debug("[Debug][ScanBG] scheduled processing task")
            #endif
        } catch {
            #if DEBUG
            VanmoLogger.library.debug("[Debug][ScanBG] schedule failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func handle(_ task: BGProcessingTask) {
        let work = Task {
            await runPendingJob()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            Task {
                await persistCheckpointAndReschedule()
            }
        }
    }

    @MainActor
    private static func runPendingJob() async {
        let container = ModelContainerFactory.makeSharedContainer()
        let context = ModelContext(container)

        let scanningPhase = ScanJobPhase.scanning.rawValue
        let pausedPhase = ScanJobPhase.paused.rawValue
        let descriptor = FetchDescriptor<ScanJobRecord>(
            predicate: #Predicate { job in
                job.phaseRaw == scanningPhase || job.phaseRaw == pausedPhase
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        guard let job = try? context.fetch(descriptor).first else { return }
        let targetConnectionId = job.connectionId
        guard let connection = try? context.fetch(
            FetchDescriptor<SavedConnection>(
                predicate: #Predicate { $0.id == targetConnectionId }
            )
        ).first else { return }

        let service = RemoteServiceFactory.create(for: connection.type)
        do {
            let password = try? KeychainManager.shared.loadString(for: "conn_\(connection.id)")
            try await service.connect(config: ConnectionConfig(from: connection, password: password))
        } catch {
            job.phase = .failed
            job.lastError = error.localizedDescription
            try? context.save()
            return
        }

        let coordinator = ScanCoordinator()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            coordinator.start(
                connection: connection,
                service: service,
                scope: job.isPartialScan ? .directory(path: job.rootPath) : .connectionRoot,
                forceFullScan: job.forceFullScan,
                modelContainer: container,
                context: context
            ) { _ in
                continuation.resume()
            }
        }

        await service.disconnect()
    }

    @MainActor
    private static func persistCheckpointAndReschedule() async {
        scheduleIfNeeded()
    }
}
#endif
