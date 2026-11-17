/// Apple-only; a no-op on Linux.
func autoreleasepool<T>(invoking body: () throws -> T) rethrows -> T { return try body() }
