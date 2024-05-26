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
  func lease<T> (_ work: (QueryRunner) async throws -> T) async throws -> T {
    return try await client.withConnection { try await work(QueryRunner($0)) }
  }
}

protocol InitableFromRow {
  init(from row: PostgresRow) throws
}

struct QueryRunner {
  private let connection: PostgresConnection

  init (_ connection: PostgresConnection) {
    self.connection = connection
  }

  func zeroOrMore<T: InitableFromRow> (_ queryText: String) async throws -> [T] {
    let result = try await connection.query(queryText).get()

    return try result.rows.map { try T.init(from: $0) }
  }
}
