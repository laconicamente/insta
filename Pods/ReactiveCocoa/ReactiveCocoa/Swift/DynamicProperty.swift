import Foundation
import enum Result.NoError

/// Wraps a `dynamic` property, or one defined in Objective-C, using Key-Value
/// Coding and Key-Value Observing.
///
/// Use this class only as a last resort! `MutableProperty` is generally better
/// unless KVC/KVO is required by the API you're using (for example,
/// `NSOperation`).
@objc public final class DynamicProperty: RACDynamicPropertySuperclass, MutablePropertyType {
	public typealias Value = AnyObject?

	fileprivate weak var object: NSObject?
	fileprivate let keyPath: String

	fileprivate var property: MutableProperty<AnyObject?>?

	/// The current value of the property, as read and written using Key-Value
	/// Coding.
	public var value: AnyObject? {
		@objc(rac_value) get {
			return object?.value(forKeyPath: keyPath) as AnyObject?
		}

		@objc(setRac_value:) set(newValue) {
			object?.setValue(newValue, forKeyPath: keyPath)
		}
	}

	/// A producer that will create a Key-Value Observer for the given object,
	/// send its initial value then all changes over time, and then complete
	/// when the observed object has deallocated.
	///
	/// - important: This only works if the object given to init() is KVO-compliant.
	///              Most UI controls are not!
	public var producer: SignalProducer<AnyObject?, NoError> {
		return property?.producer ?? .empty
	}

	public var signal: Signal<AnyObject?, NoError> {
		return property?.signal ?? .empty
	}

	/// Initializes a property that will observe and set the given key path of
	/// the given object.
	///
	/// - important: `object` must support weak references!
	///
	/// - parameters:
	///   - object: An object to be observed.
	///   - keyPath: Key path to observe on the object.
	public init(object: NSObject?, keyPath: String) {
		self.object = object
		self.keyPath = keyPath
		self.property = MutableProperty(nil)

		/// A DynamicProperty will stay alive as long as its object is alive.
		/// This is made possible by strong reference cycles.
		super.init()

		object?.rac_values(forKeyPath: keyPath, observer: nil)?
			.toSignalProducer()
			.start { event in
				switch event {
				case let .next(newValue):
					self.property?.value = newValue
				case let .failed(error):
					fatalError("Received unexpected error from KVO signal: \(error)")
				case .interrupted, .completed:
					self.property = nil
				}
			}
	}
}

// MARK: Operators

/// Binds a signal to a `DynamicProperty`, automatically bridging values to Objective-C.
public func <~ <S: SignalType>(property: DynamicProperty, signal: S) -> Disposable where S.Value: _ObjectiveCBridgeable, S.Error == NoError {
	return property <~ signal.map { $0._bridgeToObjectiveC() }
}

/// Binds a signal producer to a `DynamicProperty`, automatically bridging values to Objective-C.
public func <~ <S: SignalProducerType>(property: DynamicProperty, producer: S) -> Disposable where S.Value: _ObjectiveCBridgeable, S.Error == NoError {
	return property <~ producer.map { $0._bridgeToObjectiveC() }
}

/// Binds `destinationProperty` to the latest values of `sourceProperty`, automatically bridging values to Objective-C.
public func <~ <Source: PropertyType>(destinationProperty: DynamicProperty, sourceProperty: Source) -> Disposable where Source.Value: _ObjectiveCBridgeable {
	return destinationProperty <~ sourceProperty.producer
}
