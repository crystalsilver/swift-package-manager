/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -----------------------------------------------------------------

 An extemely simple rendition of the Xcode project model into a plist.  There
 is only enough functionality to allow serialization of Xcode projects.
*/

extension Xcode.Project: PropertyListSerializable {
    
    /// Generates and returns the contents of a `project.pbxproj` plist.  Does
    /// not generate any ancillary files, such as a set of schemes.
    ///
    /// Many complexities of the Xcode project model are not represented; we
    /// should not add functionality to this model unless it's needed, since
    /// implementation of the full Xcode project model would be unnecessarily
    /// complex.
    public func generatePlist() -> PropertyList {
        // The project plist is a bit special in that it's the archive for the
        // whole file.  We create a plist serializer and serialize the entire
        // object graph to it, and then return an archive dictionary containing
        // the serialized object dictionaries.
        let serializer = PropertyListSerializer()
        serializer.serialize(object: self)
        return .dictionary([
            "archiveVersion": .string("1"),
            "objectVersion":  .string("46"),  // Xcode 8.0
            "rootObject":     .identifier(serializer.id(of: self)),
            "objects":        .dictionary(serializer.idsToDicts),
        ])
    }
    
    /// Called by the Serializer to serialize the Project.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXProject` plist dictionary.
        // Note: we skip things like the `Products` group; they get autocreated
        // by Xcode when it opens the project and notices that they are missing.
        // Note: we also skip schemes, since they are not in the project plist.
        var dict = [String: PropertyList]()
        dict["isa"] = .string("PBXProject")
        // Since the project file is generated, we opt out of upgrade-checking.
        // FIXME: Shoule we really?  Why would we not want to get upgraded?
        dict["attributes"] = .dictionary(["LastUpgradeCheck": .string("9999")])
        dict["compatibilityVersion"] = .string("Xcode 3.2")
        dict["developmentRegion"] = .string("English")
        // Build settings are a bit tricky; in Xcode, each is stored in a named
        // XCBuildConfiguration object, and the list of build configurations is
        // in turn stored in an XCConfigurationList.  In our simplified model,
        // we have a BuildSettingsTable, with three sets of settings:  one for
        // the common settings, and one each for the Debug and Release overlays.
        // So we consider the BuildSettingsTable to be the configuration list.
        dict["buildConfigurationList"] = .identifier(serializer.serialize(object: buildSettings))
        dict["mainGroup"] = .identifier(serializer.serialize(object: mainGroup))
        dict["hasScannedForEncodings"] = .string("0")
        dict["knownRegions"] = .array([.string("en")])
        if let productGroup = productGroup {
            dict["productRefGroup"] = .identifier(serializer.id(of: productGroup))
        }
        dict["projectDirPath"] = .string(projectDir)
        dict["targets"] = .array(targets.map{ target in
            .identifier(serializer.serialize(object: target))
        })
        return dict
    }
}

/// Private helper function that constructs and returns a partial property list
/// dictionary for references.  The caller can add to the returned dictionary.
/// FIXME:  It would be nicer to be able to use inheritance to serialize the
/// attributes inherited from Reference, but but in Swift 3.0 we get an error
/// that "declarations in extensions cannot override yet".
fileprivate func makeReferenceDict(reference: Xcode.Reference, serializer: PropertyListSerializer, xcodeClassName: String) -> [String: PropertyList] {
    var dict = [String: PropertyList]()
    dict["isa"] = .string(xcodeClassName)
    dict["path"] = .string(reference.path)
    if let name = reference.name {
        dict["name"] = .string(name)
    }
    dict["sourceTree"] = .string(reference.pathBase.asString)
    return dict
}

extension Xcode.Group: PropertyListSerializable {
    
    /// Called by the Serializer to serialize the Group.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXGroup` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from Reference, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        var dict = makeReferenceDict(reference: self, serializer: serializer, xcodeClassName: "PBXGroup")
        dict["children"] = .array(subitems.map{ reference in
            // For the same reason, we have to cast as `PropertyListSerializable`
            // here; as soon as we try to make Reference conform to the protocol,
            // we get the problem of not being able to override `serialize(to:)`.
            .identifier(serializer.serialize(object: reference as! PropertyListSerializable))
        })
        return dict
    }
}

extension Xcode.FileReference: PropertyListSerializable {
    
    /// Called by the Serializer to serialize the FileReference.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXFileReference` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from Reference, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        var dict = makeReferenceDict(reference: self, serializer: serializer, xcodeClassName: "PBXFileReference")
        if let fileType = fileType {
            dict["explicitFileType"] = .string(fileType)
        }
        // FileReferences don't need to store a name if it's the same as the path.
        if name == path {
            dict["name"] = nil
        }
        return dict
    }
}

extension Xcode.Target: PropertyListSerializable {

    /// Called by the Serializer to serialize the Target.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXNativeTarget` plist dictionary.
        var dict = [String: PropertyList]()
        dict["isa"] = .string("PBXNativeTarget")
        dict["name"] = .string(name)
        // Build settings are a bit tricky; in Xcode, each is stored in a named
        // XCBuildConfiguration object, and the list of build configurations is
        // in turn stored in an XCConfigurationList.  In our simplified model,
        // we have a BuildSettingsTable, with three sets of settings:  one for
        // the common settings, and one each for the Debug and Release overlays.
        // So we consider the BuildSettingsTable to be the configuration list.
        // This is the same situation as for Project.
        dict["buildConfigurationList"] = .identifier(serializer.serialize(object: buildSettings))
        dict["buildPhases"] = .array(buildPhases.map{ phase in
            // Here we have the same problem as for Reference; we cannot inherit
            // functionality since we're in an extension.
            .identifier(serializer.serialize(object: phase as! PropertyListSerializable))
        })
        /// Private wrapper class for a target dependency relation.  This is
        /// glue between our value-based settings structures and the Xcode
        /// project model's identity-based TargetDependency objects.
        class TargetDependency: PropertyListSerializable {
            var target: Xcode.Target
            init(target: Xcode.Target) {
                self.target = target
            }
            func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
                // Create a `PBXTargetDependency` plist dictionary.
                var dict = [String: PropertyList]()
                dict["isa"] = .string("PBXTargetDependency")
                dict["target"] = .identifier(serializer.id(of: target))
                return dict
            }
        }
        dict["dependencies"] = .array(dependencies.map { dep in
            // In the Xcode project model, target dependencies are objects,
            // so we need a helper class here.
            .identifier(serializer.serialize(object: TargetDependency(target: dep.target)))
        })
        dict["productName"] = .string(productName)
        dict["productType"] = .string(productType.asString)
        if let productReference = productReference {
            dict["productReference"] = .identifier(serializer.id(of: productReference))
        }
        return dict
    }
}

/// Private helper function that constructs and returns a partial property list
/// dictionary for build phases.  The caller can add to the returned dictionary.
/// FIXME:  It would be nicer to be able to use inheritance to serialize the
/// attributes inherited from BuildPhase, but but in Swift 3.0 we get an error
/// that "declarations in extensions cannot override yet".
fileprivate func makeBuildPhaseDict(buildPhase: Xcode.BuildPhase, serializer: PropertyListSerializer, xcodeClassName: String) -> [String: PropertyList] {
    var dict = [String: PropertyList]()
    dict["isa"] = .string(xcodeClassName)
    dict["files"] = .array(buildPhase.files.map{ file in
        .identifier(serializer.serialize(object: file))
    })
    return dict
}


extension Xcode.HeadersBuildPhase: PropertyListSerializable {
    
    /// Called by the Serializer to serialize the HeadersBuildPhase.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXHeadersBuildPhase` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from BuildPhase, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        return makeBuildPhaseDict(buildPhase: self, serializer: serializer, xcodeClassName: "PBXHeadersBuildPhase")
    }
}

extension Xcode.SourcesBuildPhase: PropertyListSerializable {
    
    /// Called by the Serializer to serialize the SourcesBuildPhase.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXSourcesBuildPhase` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from BuildPhase, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        return makeBuildPhaseDict(buildPhase: self, serializer: serializer, xcodeClassName: "PBXSourcesBuildPhase")
    }
}

extension Xcode.FrameworksBuildPhase: PropertyListSerializable {
    
    /// Called by the Serializer to serialize the FrameworksBuildPhase.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXFrameworksBuildPhase` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from BuildPhase, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        return makeBuildPhaseDict(buildPhase: self, serializer: serializer, xcodeClassName: "PBXFrameworksBuildPhase")
    }
}

extension Xcode.CopyFilesBuildPhase: PropertyListSerializable {
    
    /// Called by the Serializer to serialize the FrameworksBuildPhase.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXCopyFilesBuildPhase` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from BuildPhase, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        var dict = makeBuildPhaseDict(buildPhase: self, serializer: serializer, xcodeClassName: "PBXCopyFilesBuildPhase")
        dict["dstPath"] = .string("")   // FIXME: needs to be real
        dict["dstSubfolderSpec"] = .string("")   // FIXME: needs to be real
        return dict
    }
}

extension Xcode.ShellScriptBuildPhase: PropertyListSerializable {
    
    /// Called by the Serializer to serialize the ShellScriptBuildPhase.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXShellScriptBuildPhase` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from BuildPhase, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        var dict = makeBuildPhaseDict(buildPhase: self, serializer: serializer, xcodeClassName: "PBXShellScriptBuildPhase")
        dict["shellPath"] = .string("/bin/sh")   // FIXME: should be settable
        dict["shellScript"] = .string(script)
        return dict
    }
}

extension Xcode.BuildFile: PropertyListSerializable {
    
    /// Called by the Serializer to serialize the BuildFile.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXBuildFile` plist dictionary.
        var dict = [String: PropertyList]()
        dict["isa"] = .string("PBXBuildFile")
        if let fileRef = fileRef {
            dict["fileRef"] = .identifier(serializer.id(of: fileRef))
        }
        return dict
    }
}


extension Xcode.BuildSettingsTable: PropertyListSerializable {
    
    /// Called by the Serializer to serialize the BuildFile.  It is serialized
    /// as an XCBuildConfigurationList and two additional XCBuildConfiguration
    /// objects (one for debug and one for release).
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        /// Private wrapper class for BuildSettings structures.  This is glue
        /// between our value-based settings structures and the Xcode project
        /// model's identity-based XCBuildConfiguration objects.
        class BuildSettingsDictWrapper: PropertyListSerializable {
            let name: String
            var baseSettings: BuildSettings
            var overlaySettings: BuildSettings
            let xcconfigFileRef: Xcode.FileReference?
            init(name: String, baseSettings: BuildSettings, overlaySettings: BuildSettings, xcconfigFileRef: Xcode.FileReference?) {
                self.name = name
                self.baseSettings = baseSettings
                self.overlaySettings = overlaySettings
                self.xcconfigFileRef = xcconfigFileRef
            }
            func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
                // Create a `XCBuildConfiguration` plist dictionary.
                var dict = [String: PropertyList]()
                dict["isa"] = .string("XCBuildConfiguration")
                dict["name"] = .string(name)
                // Combine the base settings and the overlay settings.
                dict["buildSettings"] = combineBuildSettingsPropertyLists(baseSettings: baseSettings.asPropertyList(), overlaySettings: overlaySettings.asPropertyList())
                // Add a reference to the base configuration, if there is one.
                if let xcconfigFileRef = xcconfigFileRef {
                    dict["baseConfigurationReference"] = .identifier(serializer.id(of: xcconfigFileRef))
                }
                return dict
            }
        }
        
        // Create a `XCConfigurationList` plist dictionary.
        var dict = [String: PropertyList]()
        dict["isa"] = .string("XCConfigurationList")
        dict["buildConfigurations"] = .array([
            // We use a private wrapper to "objectify" our two build settings
            // structures (which, being structs, are value types).
            .identifier(serializer.serialize(object: BuildSettingsDictWrapper(name: "Debug", baseSettings: common, overlaySettings: debug, xcconfigFileRef: xcconfigFileRef))),
            .identifier(serializer.serialize(object: BuildSettingsDictWrapper(name: "Release", baseSettings: common, overlaySettings: release, xcconfigFileRef: xcconfigFileRef))),
        ])
        // FIXME: What is this, and why are we setting it?
        dict["defaultConfigurationIsVisible"] = .string("0")
        // FIXME: Should we allow this to be set in the model?
        dict["defaultConfigurationName"] = .string("Debug")
        return dict
    }
}


extension Xcode.BuildSettingsTable.BuildSettings {
    
    /// Returns a property list representation of the build settings, in which
    /// every struct field is represented as a dictionary entry.  Fields of
    /// type `String` are represented as `PropertyList.string` values; fields
    /// of type `[String]` are represented as `PropertyList.array` values with
    /// `PropertyList.string` values as the array elements.  The property list
    /// dictionary only contains entries for struct fields that aren't nil.
    ///
    /// Note: BuildSettings is a value type and PropertyListSerializable only
    /// applies to classes.  Creating a property list representation is totally
    /// independent of that serialization infrastructure (though it might well
    /// be invoked during of serialization of actual model objects).
    fileprivate func asPropertyList() -> PropertyList {
        // Borderline hacky, but the main thing is that adding or changing a
        // build setting does not require any changes to the property list
        // representation code.  Using a handcoded serializer might be more
        // efficient but not even remotely as robust, and robustness is the
        // key factor for this use case, as there aren't going to be millions
        // of BuildSettings structs.
        var dict = [String: PropertyList]()
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            guard let name = child.label else {
                preconditionFailure("unnamed build settings are not supported")
            }
            switch child.value {
              case nil:
                continue
              case let value as String:
                dict[name] = .string(value)
              case let value as [String]:
                dict[name] = .array(value.map{ .string($0) })
              default:
                // FIXME: I haven't found a way of distinguishing a value of an
                // unexpected type from a value that is nil; they all seem to go
                // throught the `default` case instead of the `nil` case above.
                // Hopefully someone reading this will clue me in about what I
                // did wrong.  But currently we will silently fail to serialize
                // any struct field that isn't a `String` or a `[String]` (or
                // an optional of either of those two).
                // This would only come up if a field were to be added of a type
                // other than `String` or `[String]`.
                continue
            }
        }
        return .dictionary(dict)
    }
}


/// Private helper function that combines a base property list and an overlay
/// property list, respecting the semantics of `$(inherited)` as we go.
/// FIXME:  This should possibly be done while constructing the property list.
fileprivate func combineBuildSettingsPropertyLists(baseSettings: PropertyList, overlaySettings: PropertyList) -> PropertyList {
    // Extract the base and overlay dictionaries.
    guard case let .dictionary(baseDict) = baseSettings else {
        preconditionFailure("base settings plist must be a dictionary")
    }
    guard case let .dictionary(overlayDict) = overlaySettings else {
        preconditionFailure("overlay settings plist must be a dictionary")
    }
    
    // Iterate over the overlay values and apply them to the base.
    var resultDict = baseDict
    for (name, value) in overlayDict {
        // FIXME: We should resolve `$(inherited)` here.  The way this works is
        // that occurrences of `$(inherited)` in the overlay are replaced with
        // the overlaid value in the base.
        resultDict[name] = value
    }
    return .dictionary(resultDict)
}


/// A simple property list serializer with the same semantics as the Xcode
/// property list serializer.  Not generally reusable at this point, but only
/// because of implementation details (architecturally it isn't tied to Xcode).
fileprivate class PropertyListSerializer {
    
    /// Private struct that represents a strong reference to a serializable
    /// object.  This prevents any temporary objects from being deallocated
    /// during the serialization and replaced with other objects having the
    /// same object identifier (a violation of our assumptions)
    struct SerializedObjectRef: Hashable, Equatable {
        let object: PropertyListSerializable
        init(_ object: PropertyListSerializable) {
            self.object = object
        }
        var hashValue: Int {
            return ObjectIdentifier(object).hashValue
        }
        static func ==(lhs: SerializedObjectRef, rhs: SerializedObjectRef) -> Bool {
            return lhs.object === rhs.object
        }
    }
    
    /// Maps objects to the identifiers that have been assigned to them.  The
    /// next identifier to be assigned is always one greater than the number
    /// of entries in the mapping.
    var objsToIds = [SerializedObjectRef: String]()
    
    /// Maps serialized objects ids to dictionaries.  This may contain fewer
    /// entries than `objsToIds`, since ids are assigned upon reference, but
    /// plist dictionaries are created only upon actual serialization.  This
    /// dictionary is what gets written to the property list.
    var idsToDicts = [String: PropertyList]()
    
    /// Returns the identifier for the object, assigning one if needed.
    func id(of object: PropertyListSerializable) -> String {
        // We need a "serialized object ref" wrapper for the `objsToIds` map.
        let serObjRef = SerializedObjectRef(object)
        if let id = objsToIds[serObjRef] {
            return id
        }
        // We currently always assign identifiers starting at 1 and going up.
        // FIXME: This is a suboptimal format for object identifier strings;
        // for debugging purposes they should at least sort in numeric order.
        let id = "OBJ_\(objsToIds.count + 1)"
        objsToIds[serObjRef] = id
        return id
    }
    
    /// Serializes `object` by asking it to construct a plist dictionary and
    /// then adding that dictionary to the serializer.  This may in turn cause
    /// recursive invocations of `serialize(object:)`; the closure of these
    /// invocations end up serializing the whole object graph.
    @discardableResult func serialize(object: PropertyListSerializable) -> String {
        // Assign an id for the object, if it doesn't already have one.
        let id = self.id(of: object)
        
        // If that id is already in `idsToDicts`, we've detected recursion or
        // repeated serialization.
        precondition(idsToDicts[id] == nil, "tried to serialize \(object) twice")
        
        // Set a sentinel value in the `idsToDicts` mapping to detect recursion.
        idsToDicts[id] = .dictionary([:])
        
        // Now recursively serialize the object, and store the result (replacing
        // the sentinel).
        idsToDicts[id] = .dictionary(object.serialize(to: self))
        
        // Finally, return the identifier so the caller can store it (usually in
        // an attribute in its own serialization dictionary).
        return id
    }
}


fileprivate protocol PropertyListSerializable: class {
    /// Called by the Serializer to construct and return a dictionary for a
    /// serializable object.  The entries in the dictionary should represent
    /// the receiver's attributes and relationships, as PropertyList values.
    ///
    /// Every object that is written to the Serializer is assigned an id (an
    /// arbitrary but unique string).  Forward references can use `id(of:)`
    /// of the Serializer to assign and access the id before the object is
    /// actually written.
    ///
    /// Implementations can use the Serializer's `serialize(object:)` method
    /// to serialize owned objects (getting an id to the serialized object,
    /// which can be stored in one of the attributes) or can use the `id(of:)`
    /// method to store a reference to an unowned object.
    ///
    /// The implementation of this method for each serializable objects looks
    /// something like this:
    ///
    ///   // Create a `PBXSomeClassOrOther` plist dictionary.
    ///   var dict = [String: PropertyList]()
    ///   dict["isa"] = .string("PBXSomeClassOrOther")
    ///   dict["name"] = .string(name)
    ///   if let path = path { dict["path"] = .string(path) }
    ///   dict["mainGroup"] = .identifier(serializer.serialize(object: mainGroup))
    ///   dict["subitems"] = .array(subitems.map{ .string($0.id) })
    ///   dict["cross-ref"] = .identifier(serializer.id(of: unownedObject))
    ///   return dict
    ///
    /// FIXME: I'm not totally happy with how this looks.  It's far too clunky
    /// and could be made more elegant.  However, since the Xcode project model
    /// is static, this is not something that will need to evolve over time.
    /// What does need to evolve, which is how the project model is constructed
    /// from the package contents, is where the elegance and simplicity really
    /// matters.  So this is acceptable for now in the interest of getting it
    /// done.
    
    /// Should create and return a property list dictionary of the object's
    /// attributes.  This function may also use the serializer's `serialize()`
    /// function to serialize other objects, and may use `id(of:)` to access
    /// ids of objects that either have or will be serialized.
    func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList]
}


/// A very simple representation of a property list.  Note that the `identifier`
/// enum is not strictly necessary, but useful to semantically distinguish the
/// strings that represents object identifiers from those that are just data.
public enum PropertyList {
    case identifier(String)
    case string(String)
    case array([PropertyList])
    case dictionary([String: PropertyList])
}


/// Private struct to generate indentation strings.
fileprivate struct Indentation: CustomStringConvertible {
    var level: Int = 0
    mutating func increase() {
        level += 1
        precondition(level > 0, "indentation level overflow")
    }
    mutating func decrease() {
        precondition(level > 0, "indentation level underflow")
        level -= 1
    }
    var description: String {
        return String(repeating: "   ", count: level)
    }
}

/// Escapes the string for plist.
/// Finds the instances of quote (") and backward slash (\) and prepends
/// the escape character backward slash (\).
/// FIXME: Reconcile this with the one that Ankit has meanwhile checked in.
fileprivate func escape(string: String) -> String {
    func needsEscape(_ char: UInt8) -> Bool {
        return char == UInt8(ascii: "\\") || char == UInt8(ascii: "\"")
    }

    guard let pos = string.utf8.index(where: needsEscape) else {
        return string
    }
    var newString = String(string.utf8[string.utf8.startIndex..<pos])!
    for char in string.utf8[pos..<string.utf8.endIndex] {
        if needsEscape(char) {
            newString += "\\"
        }
        newString += String(UnicodeScalar(char))
    }
    return newString
}

/// Private function to generate OPENSTEP-style plist representation.
fileprivate func generatePlistRepresentation(plist: PropertyList, indentation: Indentation) -> String {
    // Do the appropriate thing for each type of plist node.
    switch plist {
        
      case .identifier(let ident):
        // FIXME: we should assert that the identifier doesn't need quoting
        return ident
        
      case .string(let string):
        return "\"" + escape(string: string) + "\""
        
      case .array(let array):
        var indent = indentation
        var str = "(\n"
        indent.increase()
        for item in array {
            str += "\(indent)\(generatePlistRepresentation(plist: item, indentation: indent)),\n"
        }
        indent.decrease()
        str += "\(indent))"
        return str
        
      case .dictionary(let dict):
        var indent = indentation
        let dict = dict.sorted{
            // Make `isa` sort first (just for readability purposes).
            switch ($0.key, $1.key) {
              case ("isa", "isa"): return false
              case ("isa", _): return true
              case (_, "isa"): return false
              default: return $0.key < $1.key
            }
        }
        var str = "{\n"
        indent.increase()
        for item in dict {
            str += "\(indent)\(item.key) = \(generatePlistRepresentation(plist: item.value, indentation: indent));\n"
        }
        indent.decrease()
        str += "\(indent)}"
        return str
    }
}

extension PropertyList: CustomStringConvertible {
    public var description: String {
        return generatePlistRepresentation(plist: self, indentation: Indentation())
    }
}
