import Foundation
import PostgresNIO

struct Postgres {
  private let client: PostgresClient

  init (configuration: PostgresClient.Configuration) {
    client = .init(configuration: configuration)
  }

  // TODO: This feels so wrong!
  func connect () async -> TaskGroup<Void>.Element {
    async let taskGroup = withTaskGroup(of: Void.self) { tasks in
      tasks.addTask {
        await client.run()
      }
    }

    return await taskGroup
  }

  // TODO: Client will rety forever when it fails to connect to Postrges.
  func now () async -> Date {
    do {
      let sequence = try await client.query("select now()")
      let row = try await sequence.collect().first!

      return try row.decode(Date.self)
    }
    catch {
      fatalError("Query failed: \(String(reflecting: error))")
    }
  }
}
