#ifndef SCANNER_H
#define SCANNER_H

// Main public header for scanner functionality
// Include this header to use scanners - the factory will create the appropriate type

#include "scanner/scanner_base.h"

// Factory function is defined in scanner_base.h as a static method:
// Scanner* Scanner::create(DataType dataType, size_t maxResults, size_t alignment);

// Usage:
//   Scanner* scanner = Scanner::create(DataType::INT, 10000, 4);
//   scanner->firstScan(ScanType::EXACT, &value);
//   // ... use scanner ...
//   delete scanner;

#endif
