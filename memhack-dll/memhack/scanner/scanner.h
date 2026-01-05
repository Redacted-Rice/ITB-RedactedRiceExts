#ifndef SCANNER_H
#define SCANNER_H

// Main public header for scanner functionality
// Include specific scanner types

#include "scanner_base.h"
#include "scanner_basic.h"
#include "scanner_sequence.h"
#include "scanner_struct.h"

// Scanners are type-specific. You must create the appropriate scanner directly
//   BasicScanner* scanner = BasicScanner::create(BasicScanner::DataType::INT, 10000, 4);
//   SequenceScanner* scanner = SequenceScanner::create(SequenceScanner::DataType::STRING, 10000, 1);
//   StructScanner* scanner = StructScanner::create(10000, 1);
//
// Lua bindings handle creation of any type with a single interface. Currently this is not
// supported on the C side

#endif
