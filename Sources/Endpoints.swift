import CoreLocation
import PostgresNIO

struct Endpoints {
  static func commonData (_ queries: QueryRunner) async throws -> CommonData {
    let categories: [Category] = try await queries.zeroOrMore("select id, name from categories order by id asc")
    let dict: [Int: String] = categories.reduce(into: [:]) { $0[Int($1.id)] = $1.name }

    return .init(categories: dict)
  }

  static func places (_ queries: QueryRunner) async throws -> [Place] {
    return try await queries.zeroOrMore("""
      select 
        id,
        created,
        updated,
        name,
        address,
        latitude(coordinate) as latitude,
        longitude(coordinate) as longitude,
        category_id as category
      from
        places
    """)
  }
}

// MARK: - Category

struct Category {
  let id: UInt16
  let name: String
}

extension Category: InitableFromRow {
  init (from row: PostgresRow) throws {
    var parsedId: UInt16?
    var parsedName: String?
    for cell in row {
      switch cell.columnName {
        case "id":
          precondition(cell.dataType == .int2 && cell.format == .binary)
          parsedId = UInt16(try cell.decode(Int16.self))

        case "name":
          precondition(cell.dataType == .text && cell.format == .binary)
          parsedName = try cell.decode(String.self)

        default:
          continue
      }
    }

    self.id = parsedId!
    self.name = parsedName!
  }
}

// MARK: - CommonData

struct CommonData: Codable {
  /// Map of category IDs to their names.
  ///
  /// Key must be Int, so it serializes into an object, instead of array of `[key, value, key2, value2, ...]`.
  let categories: [Int: String]
}

// MARK: - Place

struct Place: Codable {
  let id: Int32
  let created: Date
  let updated: Date

  let name: String
  let address: String
  let latitude: Double
  let longitude: Double
  let category: Int32
}

extension Place: InitableFromRow {
  init (from row: PostgresNIO.PostgresRow) throws {
    var parsedId: Int32?
    var parsedCreated: Date?
    var parsedUpdated: Date?

    var parsedName: String?
    var parsedAddress: String?
    var parsedLatitude: Double?
    var parsedLongitude: Double?
    var parsedCategory: Int32?

    for cell in row {
      switch cell.columnName {
        case "id":
          precondition(cell.dataType == .int4 && cell.format == .binary)
          parsedId = try cell.decode(Int32.self)

        case "created":
          parsedCreated = try cell.decode(Date.self)
          
        case "updated":
          parsedUpdated = try cell.decode(Date.self)

        case "name":
          // TODO: Column "name" is `citext`. It's unknwon to PostgresNIO. Find out how to register "custom" types.
          // precondition(cell.dataType == .text && cell.format == .binary, String(describing: cell.da))
          parsedName = String(buffer: cell.bytes!)

        case "address":
          parsedAddress = String(buffer: cell.bytes!)

        case "latitude":
          parsedLatitude = try cell.decode(Double.self)

        case "longitude":
          parsedLongitude = try cell.decode(Double.self)

        case "category":
          parsedCategory = try cell.decode(Int32.self)

        default:
          continue
      }
    }

    self.id = parsedId!
    self.created = parsedCreated!
    self.updated = parsedUpdated!

    self.name = parsedName!
    self.address = parsedAddress!
    self.latitude = parsedLatitude!
    self.longitude = parsedLongitude!
    self.category = parsedCategory!
  }
}
