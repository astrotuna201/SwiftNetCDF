//
//  Nc.swift
//  SwiftNetCDF
//
//  Created by Patrick Zippenfenig on 2019-09-10.
//


import CNetCDF
import Foundation

struct SwiftNetCDF {
    var text = "Hello, World!"
    var netCDFVersion = String(cString: nc_inq_libvers())
}

enum NetCDFError: Error {
    case ncerror(code: Int32, error: String)
    case invalidVariable
    case badNcid
    case badVarid
    case badGroupid
    case badName
    case attributeNotFound
    case valueCanNotBeConverted
    
    init(ncerr: Int32) {
        switch ncerr {
        case NC_ENOTVAR: self = .invalidVariable
        case NC_EBADID: self = .badNcid
        case NC_ENOTVAR: self = .badVarid
        case NC_EBADGRPID: self = .badGroupid
        case NC_EBADNAME: self = .badName
        case NC_ENOTATT: self = .attributeNotFound
        default:
            let error = String(cString: nc_strerror(ncerr))
            self = .ncerror(code: ncerr, error: error)
        }
    }
}

/**
 This struct wraps NetCDF C library functions to a more safe Swift syntax.
 A lock is used to ensure the library is not acessed from multiple threads simultaniously.
 */
public struct Nc {
    /**
     A Lock to serialise access to the NetCDF C library.
     */
    private static let lock = Lock()
    
    /**
     Reused buffer which some NetCDF routines can write names into. Afterwards it should be converted to a Swift String.
     The buffer should only be used with a thread lock.
     */
    private static var maxNameBuffer = [Int8](repeating: 0, count: Int(NC_MAX_NAME+1))
    
    /**
     Execute a netcdf command in a thread safe lock and check the error code. Throw an exception otherwise.
     */
    private static func exec(_ fn: () -> Int32) throws {
        let ncerr = Nc.lock.withLock(fn)
        guard ncerr == NC_NOERR else {
            throw NetCDFError(ncerr: ncerr)
        }
    }
    
    /**
     Execute a closure which takes a buffer for a netcdf variable NC_MAX_NAME const string.
     Afterwards the buffer is converted to a Swift string
     */
    private static func nc_max_name(_ fn: (UnsafeMutablePointer<Int8>) -> Int32) throws -> String {
        return try Nc.lock.withLock {
            let error = fn(&Nc.maxNameBuffer)
            guard error == NC_NOERR else {
                throw NetCDFError(ncerr: error)
            }
            return String(cString: &Nc.maxNameBuffer)
        }
    }
}

public extension Nc {
    static var NC_UNLIMITED: Int { return CNetCDF.NC_UNLIMITED }
    
    static var NC_GLOBAL: Int32 { return CNetCDF.NC_GLOBAL }
    
    /// Get all group IDs of a group id
    static func inq_grps(ncid: Int32) throws -> [Int32] {
        var count: Int32 = 0
        try exec {
            nc_inq_grps(ncid, &count, nil)
        }
        var ids = [Int32](repeating: 0, count: Int(count))
        try exec {
            nc_inq_grps(ncid, nil, &ids)
        }
        return ids
    }
    
    static func open(path: String, omode: Int32) throws -> Int32 {
        var ncid: Int32 = 0
        try exec {
            nc_open(path, omode, &ncid)
        }
        return ncid
    }
    
    static func open(path: String, allowWrite: Bool) throws -> Int32 {
        return try open(path: path, omode: allowWrite ? NC_WRITE : 0)
    }
    
    static func create(path: String, cmode: Int32) throws -> Int32 {
        var ncid: Int32 = 0
        try exec {
            nc_create(path, cmode, &ncid)
        }
        return ncid
    }
    
    static func create(path: String, overwriteExisting: Bool, useNetCDF4: Bool) throws -> Int32 {
        var cmode = Int32(0)
        if overwriteExisting == false {
            cmode |= NC_NOCLOBBER
        }
        if useNetCDF4 {
            cmode |= NC_NETCDF4
        }
        return try create(path: path, cmode: cmode)
    }
    
    static func sync(ncid: Int32) throws {
        try exec {
            nc_sync(ncid)
        }
    }
    
    static func inq_natts(ncid: Int32) throws -> Int32 {
        var count: Int32 = 0
        try exec {
            nc_inq_natts(ncid, &count)
        }
        return count
    }
    
    static func inq_type(ncid: Int32, typeid: Int32) throws -> (name: String, size: Int) {
        var size = 0
        let name = try nc_max_name {
            nc_inq_type(ncid, typeid, $0, &size)
        }
        return (name, size)
    }
    
    static func inq_user_type(ncid: Int32, typeid: Int32) throws -> (name: String, size: Int, baseTypeId: Int32, numberOfFields: Int, classType: Int32) {
        
        var size = 0
        var baseTypeId: Int32 = 0
        var numberOfFields = 0
        var classType: Int32 = 0
        let name = try nc_max_name {
            nc_inq_user_type(ncid, typeid, $0, &size, &baseTypeId, &numberOfFields, &classType)
        }
        return (name, size, baseTypeId, numberOfFields, classType)
    }
    
    /// Get all variable IDs of a group id
    static func inq_varids(ncid: Int32) throws -> [Int32] {
        var count: Int32 = 0
        try exec {
            nc_inq_varids(ncid, &count, nil)
        }
        var ids = [Int32](repeating: 0, count: Int(count))
        try exec {
            nc_inq_varids(ncid, nil, &ids)
        }
        return ids
    }
    
    /// Get the name of a group
    static func inq_grpname(ncid: Int32) throws -> String {
        var nameLength = 0
        try exec {
            nc_inq_grpname_len(ncid, &nameLength)
        }
        var nameBuffer = [Int8](repeating: 0, count: nameLength) // CHECK +1 needed?
        try exec {
            nc_inq_grpname(ncid, &nameBuffer)
        }
        return String(cString: nameBuffer)
    }
    
    /// Define a new group
    static func def_grp(ncid: Int32, name: String) throws -> Int32 {
        var newNcid: Int32 = 0
        try exec {
            nc_def_grp(ncid, name, &newNcid)
        }
        return newNcid
    }
    
    /// Get a variable by name
    static func inq_varid(ncid: Int32, name: String) throws -> Int32 {
        var id: Int32 = 0
        try exec { nc_inq_varid(ncid, name, &id) }
        return id
    }
    
    /// Get a group by name
    static func inq_grp_ncid(ncid: Int32, name: String) throws -> Int32 {
        var id: Int32 = 0
        try exec { nc_inq_grp_ncid(ncid, name, &id) }
        return id
    }
    
    /// Close the netcdf file
    static func close(ncid: Int32) throws {
        try exec {
            nc_close(ncid)
        }
    }
    
    /**
     Get a list of IDs of unlimited dimensions.
     In netCDF-4 files, it's possible to have multiple unlimited dimensions. This function returns a list of the unlimited dimension ids visible in a group.
     Dimensions are visible in a group if they have been defined in that group, or any ancestor group.
     */
    static func inq_unlimdims(ncid: Int32) throws -> [Int32] {
        // Get the number of dimensions
        var count: Int32 = 0
        try exec {
            nc_inq_unlimdims(ncid, &count, nil)
        }
        // Allocate array and get the IDs
        var dimensions = [Int32](repeating: 0, count: Int(count))
        try exec {
            nc_inq_unlimdims(ncid, nil, &dimensions)
        }
        return dimensions
    }
    
    /// Get all variable IDs of a group id
    static func inq_varndims(ncid: Int32, varid: Int32) throws -> Int32 {
        var count: Int32 = 0
        try exec {
            nc_inq_varndims(ncid, varid, &count)
        }
        return count
    }
    
    static func inq_dimids(ncid: Int32, includeParents: Bool) throws -> [Int32] {
        // Get the number of dimensions
        var count: Int32 = 0
        try exec {
            nc_inq_dimids(ncid, &count, nil, includeParents ? 1 : 0)
        }
        // Allocate array and get the IDs
        var ids = [Int32](repeating: 0, count: Int(count))
        try exec {
            nc_inq_dimids(ncid, nil, &ids, includeParents ? 1 : 0)
        }
        return ids
    }
    
    
    static func inq_var(ncid: Int32, varid: Int32) throws -> (name: String, typeid: Int32, dimensionIds: [Int32], nAttributes: Int32) {
        let nDimensions = try inq_varndims(ncid: ncid, varid: varid)
        var dimensionIds = [Int32](repeating: 0, count: Int(nDimensions))
        var nAttribudes: Int32 = 0
        var typeid: Int32 = 0
        let name = try nc_max_name {
            nc_inq_var(ncid, varid, $0, &typeid, nil, &dimensionIds, &nAttribudes)
        }
        return (name, typeid, dimensionIds, nAttribudes)
    }
    
    static func def_var(ncid: Int32, name: String, typeid: Int32, dimensionIds: [Int32]) throws -> Int32 {
        var varid: Int32 = 0
        try exec {
            nc_def_var(ncid, name, typeid, Int32(dimensionIds.count), dimensionIds, &varid)
        }
        return varid
    }
    
    static func inq_dim(ncid: Int32, dimid: Int32) throws -> (name: String, length: Int) {
        var len: Int = 0
        let name = try nc_max_name {
            nc_inq_dim(ncid, dimid, $0, &len)
        }
        return (name, len)
    }
    
    static func def_dim(ncid: Int32, name: String, length: Int) throws -> Int32 {
        var dimid: Int32 = 0
        try exec {
            nc_def_dim(ncid, name, length, &dimid)
        }
        return dimid
    }
    
    static func inq_attname(ncid: Int32, varid: Int32, attid: Int32) throws -> String {
        return try nc_max_name {
            nc_inq_attname(ncid, varid, attid, $0)
        }
    }
    
    static func inq_att(ncid: Int32, varid: Int32, name: String) throws -> (typeid: Int32, length: Int) {
        var typeid: Int32 = 0
        var len: Int = 0
        try exec {
            nc_inq_att(ncid, varid, name, &typeid, &len)
        }
        return (typeid, len)
    }
    
    static func put_att(ncid: Int32, varid: Int32, name: String, type: Int32, length: Int, ptr: UnsafeRawPointer) throws {
        try exec {
            nc_put_att(ncid, varid, name, type, length, ptr)
        }
    }
    
    static func put_att_text(ncid: Int32, varid: Int32, name: String, length: Int, text: String) throws {
        try exec {
            nc_put_att_text(ncid, varid, name, length, text)
        }
    }
    
    
    static func inq_attlen(ncid: Int32, varid: Int32, name: String) throws -> Int {
        var len: Int = 0
        try exec {
            nc_inq_attlen(ncid, varid, name, &len)
        }
        return len
    }
    
    static func get_att(ncid: Int32, varid: Int32, name: String, buffer: UnsafeMutableRawPointer) throws {
        try exec {
            nc_get_att(ncid, varid, name, buffer)
        }
    }
    
    static func free_string(len: Int, stringArray: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>) {
        /// no error should be possible
        try! exec {
            nc_free_string(len, stringArray)
        }
    }
    
    static func get_vara(ncid: Int32, varid: Int32, offset: [Int], count: [Int], buffer: UnsafeMutableRawPointer) throws {
        try exec {
            nc_get_vara(ncid, varid, offset, count, buffer)
        }
    }
    
    static func get_vars(ncid: Int32, varid: Int32, offset: [Int], count: [Int], stride: [Int], buffer: UnsafeMutableRawPointer) throws {
        try exec {
            nc_get_vars(ncid, varid, offset, count, stride, buffer)
        }
    }
    
    static func put_vara(ncid: Int32, varid: Int32, offset: [Int], count: [Int], ptr: UnsafeRawPointer) throws {
        try exec {
            nc_put_vara(ncid, varid, offset, count, ptr)
        }
    }
    static func put_vars(ncid: Int32, varid: Int32, offset: [Int], count: [Int], stride: [Int], ptr: UnsafeRawPointer) throws {
        try exec {
            nc_put_vars(ncid, varid, offset, count, stride, ptr)
        }
    }
    
    static func def_var_deflate(ncid: Int32, varid: Int32, shuffle: Bool, deflate: Bool, deflate_level: Int32) throws {
        try exec {
            nc_def_var_deflate(ncid, varid, shuffle ? 1 : 0, deflate ? 1 : 0, deflate_level)
        }
    }
    
    static func def_var_chunking(ncid: Int32, varid: Int32, type: Chunking, chunks: [Int]) throws {
        try exec {
            return nc_def_var_chunking(ncid, varid, type.netcdfValue, chunks)
        }
    }
    
    static func def_var_flechter32(ncid: Int32, varid: Int32, enable: Bool) throws {
        try exec {
            nc_def_var_fletcher32(ncid, varid, enable ? 1 : 0)
        }
    }
    
    static func def_var_endian(ncid: Int32, varid: Int32, type: Endian) throws {
        try exec {
            nc_def_var_endian(ncid, varid, type.netcdfValue)
        }
    }
    
    static func def_var_filter(ncid: Int32, varid: Int32, id: UInt32, params: [UInt32]) throws {
        try exec {
            nc_def_var_filter(ncid, varid, id, params.count, params)
        }
    }
}

public enum Chunking {
    case chunked
    case contingous
    
    fileprivate var netcdfValue: Int32 {
        switch self {
        case .chunked: return NC_CHUNKED
        case .contingous: return NC_CONTIGUOUS
        }
    }
}

public enum Endian {
    case native
    case little
    case big
    
    fileprivate var netcdfValue: Int32 {
        switch self {
        case .native: return NC_ENDIAN_NATIVE
        case .little: return NC_ENDIAN_LITTLE
        case .big: return NC_ENDIAN_BIG
        }
    }
}