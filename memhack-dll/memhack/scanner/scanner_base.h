#ifndef SCANNER_BASE_H
#define SCANNER_BASE_H

#include <vector>
#include <cstdint>
#include <string>
#include <Windows.h>

// Forward declare for SafeMemory::Region
namespace SafeMemory {
	struct Region;
}

// Buffer size for scanning - use 64KB chunks for good cache performance
const size_t SCAN_BUFFER_SIZE = 65536;

// Rescan batching threshold - batch results within 4KB of each other
const size_t CHUNK_THRESHOLD = 4096;

// Maximum size for sequence searches (strings/byte arrays)
// This prevents excessive memory allocation and overlap calculations
// MUST be less than SCAN_BUFFER_SIZE for overlap logic to work correctly
const size_t MAX_SEQUENCE_SIZE = 4096;

// Compile-time assertion to ensure buffer is larger than max sequence
static_assert(SCAN_BUFFER_SIZE > MAX_SEQUENCE_SIZE,
              "SCAN_BUFFER_SIZE must be greater than MAX_SEQUENCE_SIZE for overlap to work");

// Float comparison epsilons
const float FLOAT_EPSILON = 0.0001f;
const double DOUBLE_EPSILON = 0.00000001;

// Scan types
enum class ScanType {
	EXACT,
	INCREASED,
	DECREASED,
	CHANGED,
	UNCHANGED,
	NOT
};

// Data types
enum class DataType {
	BYTE,
	INT,
	FLOAT,
	DOUBLE,
	BOOL,
	STRING, // Fixed length string. Does not check null term. If needed use byte array for now at least
	BYTE_ARRAY
};

union ScanValue {
	uint8_t byteValue;
	int32_t intValue;
	float floatValue;
	double doubleValue;
	bool boolValue;
};

// Single scan result
// Will only include basic type data. Sequences are not stored
struct ScanResult {
	uintptr_t address;
	ScanValue value;
	ScanValue oldValue;
	bool hasOldValue;

	ScanResult() : address(0), hasOldValue(false) {
		value.doubleValue = 0.0;
		oldValue.doubleValue = 0.0;
	}
};

// Base Scanner class - abstract interface
// All scanner implementations derive from this to provide a unified interface
// and consistent interaction but allowing us to use different optimized implementation
// for various types under the hood
class Scanner {
public:
	virtual ~Scanner() {}

	// Factory method to create appropriate scanner based on data type
	static Scanner* create(DataType dataType, size_t maxResults, size_t alignment);

	// Public scan methods (implemented in base with template method pattern)
	void firstScan(ScanType scanType, const void* targetValue, size_t valueSize = 0);
	void rescan(ScanType scanType, const void* targetValue, size_t valueSize = 0);
	virtual void reset();

	// Virtual method with default implementation (only needed for sequence types)
	virtual bool readSequenceBytes(uintptr_t address, std::vector<uint8_t>& outBytes) const {
		return false; // Default: not supported
	}

	// pure virtual getters
	virtual size_t getDataTypeSize() const = 0;
	virtual bool isSequenceType() const = 0;

	// Getters
	virtual bool isFirstScan() const { return !firstScanDone; }
	virtual DataType getDataType() const { return dataType; }
	virtual ScanType getLastScanType() const { return lastScanType; }

	// Only valid if isSequenceType() == true
	virtual const std::vector<uint8_t>& getSearchSequence() const {
		static std::vector<uint8_t> empty;
		return empty;
	}
	virtual size_t getSequenceSize() const { return 0; }

	// Results
	virtual const std::vector<ScanResult>& getResults() const { return results; }
	virtual size_t getResultCount() const { return results.size(); }
	virtual bool isMaxResultsReached() const { return maxResultsReached; }

	// Error handling
	virtual void clearErrors() { errors.clear(); }
	virtual const std::vector<std::string>& getErrors() const { return errors; }
	virtual size_t getInvalidAddressCount() const { return invalidAddressCount; }
	virtual bool hasError() const { return !errors.empty(); }

	// Timing
	virtual void setCheckTiming(bool enabled) { checkTiming = enabled; }
	virtual bool getCheckTiming() const { return checkTiming; }

protected:
	// Common state shared by all scanners
	DataType dataType;
	size_t maxResults;
	size_t alignment;
	std::vector<ScanResult> results;
	bool firstScanDone;
	bool maxResultsReached;
	bool checkTiming;
	ScanType lastScanType;

	// Error tracking (mutable so const methods can log errors)
	mutable std::vector<std::string> errors;
	mutable size_t invalidAddressCount;

	// Protected constructor for derived classes
	Scanner(DataType dataType, size_t maxResults, size_t alignment);

	// Hook for scanner-specific setup (e.g., storing search sequence)
	// Called by base class before firstScan and rescan
	// Default implementation does nothing
	virtual bool setupScanCommon(ScanType scanType, const void* targetValue, size_t valueSize) {
		return true;
	}

	// Hook for scanner-specific scan type validation
	virtual bool validateFirstScanType(ScanType scanType) {
		return true;
	}

	// -------- Default first scan related functions ---------

	// Base class provides default region loop implementation
	virtual void firstScanImpl(ScanType scanType, const void* targetValue, size_t valueSize);

	// Scan a single region - base class provides default buffered implementation
	virtual void scanRegion(uintptr_t base, size_t size, ScanType scanType, const void* targetValue);

	// Derived classes must implement chunk scanning
	virtual void scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
	                               ScanType scanType, const void* targetValue) = 0;

	// -------- Default rescan related functions ---------

	// Rescan only the matched entry
	// Has a default implemnetation that can be overridden by derived classes
	virtual void rescanImpl(ScanType scanType, const void* targetValue, size_t valueSize);

	void processResultsInRegion(MEMORY_BASIC_INFORMATION& mbi, size_t& resultIdx,
	                             ScanType scanType, const void* targetValue,
	                             std::vector<ScanResult>& newResults,
	                             std::vector<uint8_t>& buffer);
	void rescanResultBatch(const std::vector<ScanResult>& oldResults, size_t batchStart, size_t batchEnd,
	                       uintptr_t chunkStart, size_t chunkSize, const uint8_t* buffer,
	                       ScanType scanType, const void* targetValue, std::vector<ScanResult>& newResults);

	// Direct result processing - base class handles common logic
	void rescanResultDirect(const ScanResult& oldResult, uintptr_t regionEnd,
	                        ScanType scanType, const void* targetValue,
	                        std::vector<ScanResult>& newResults);

	// Derived classes implement these validation methods
	// Validate value directly from memory with try/catch protection
	virtual bool validateValueDirect(uintptr_t address, uintptr_t regionEnd,
	                                  ScanType scanType, const void* targetValue,
	                                  ScanResult& outResult) const = 0;

	// Validate value from buffer (already safe - no try/catch needed)
	virtual bool validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                                    uintptr_t actualAddress, ScanType scanType, const void* targetValue,
	                                    ScanResult& outResult) const = 0;

	// -------- End of default rescan related functions ---------

	// Common helper methods implemented in base
	void addError(const char* format, ...) const;
	void reportInvalidAddressStats();

	// Safely copy memory with try/catch (static utility)
	static bool safeCopyMemory(void* dest, const void* src, size_t size);
};

#endif
