/**
  Copyright (C) 2012-2013 by Autodesk, Inc.
  All rights reserved.

  Heidenhain/MANUALplus post processor configuration.

  $Revision: 37254 $
  $Date: 2014-05-26 11:17:00 +0200 (ma, 26 maj 2014) $
*/

description = "Github- Generic Heidenhain/MANUALplus Turning";
vendor = "Autodesk, Inc.";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2012-2013 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

extension = "nc";
programNameIsInteger = true;
setCodePage("ascii");

capabilities = CAPABILITY_TURNING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion



// user-defined properties
properties = {
  writeMachine: false, // write machine
  preloadTool: false, // preloads next tool on tool change if any
  showSequenceNumbers: true, // show sequence numbers
  sequenceNumberStart: 10, // first sequence number
  sequenceNumberIncrement: 5, // increment for sequence numbers
  optionalStop: true, // optional stop
  separateWordsWithSpace: true, // specifies that the words should be separated with a white space
  useRadius: true, // specifies that arcs should be output using the radius (R word) instead of the I, J, and K words.
  maximumSpindleSpeed: 100 * 60 // specifies the maximum spindle speed
};



var permittedCommentChars = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,=_-";

var mapCoolantTable = new Table(
  [9, 8],
  {initial:COOLANT_OFF, force:true},
  "Invalid coolant mode"
);

var gFormat = createFormat({prefix:"G", width:2, zeropad:true, decimals:1});
var mFormat = createFormat({prefix:"M", width:2, zeropad:true, decimals:1});
var hFormat = createFormat({prefix:"H", width:2, zeropad:true, decimals:1});
var dFormat = createFormat({prefix:"D", width:2, zeropad:true, decimals:1});

var xFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true, scale:2}); // diameter mode
var yFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var zFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var rFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true}); // radius
var feedFormat = createFormat({decimals:(unit == MM ? 0 : 1), forceDecimal:true});
var toolFormat = createFormat({decimals:0});
var rpmFormat = createFormat({decimals:0});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-999
var taperFormat = createFormat({decimals:1, scale:DEG});

var xOutput = createVariable({prefix:"X"}, xFormat);
var yOutput = createVariable({prefix:"Y"}, yFormat);
var zOutput = createVariable({prefix:"Z"}, zFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, rpmFormat);
var dOutput = createVariable({}, dFormat);

// circular output
var iOutput = createVariable({prefix:"I"}, xFormat); // diameter
var jOutput = createVariable({prefix:"J"}, yFormat);
var kOutput = createVariable({prefix:"K"}, zFormat);

var gMotionModal = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var gFeedModeModal = createModal({}, gFormat); // modal group 5 // G94-95
var gSpindleModeModal = createModal({}, gFormat); // modal group 5 // G96-97
var gCycleModal = createModal({}, gFormat); // modal group 9 // G71, ...

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;
var currentWorkOffset;

/**
  Writes the specified block.
*/
function writeBlock() {
  if (properties.showSequenceNumbers) {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("(" + filterText(String(text).toUpperCase(), permittedCommentChars) + ")");
}

function onOpen() {

  yOutput.disable();
  jOutput.disable();

  if (!properties.separateWordsWithSpace) {
    setWordSeparator("");
  }

  sequenceNumber = properties.sequenceNumberStart;
  writeln("%");

  if (programName) {
    var programId;
    try {
      programId = getAsInt(programName);
    } catch(e) {
      error(localize("Program name must be a number."));
    }
    if (!((programId >= 1) && (programId <= 9999))) {
      error(localize("Program number is out of range."));
    }
    var oFormat = createFormat({width:4, zeropad:true, decimals:0});
    if (programComment) {
      writeln("O" + oFormat.format(programId) + " (" + filterText(String(programComment).toUpperCase(), permittedCommentChars) + ")");
    } else {
      writeln("O" + oFormat.format(programId));
    }
  } else {
    error(localize("Program name has not been specified."));
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

  // feed per min
  writeBlock(gFeedModeModal.format(94));

  writeBlock(
    gFormat.format(26), sOutput.format(properties.maximumSpindleSpeed)
  );
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X, Y, Z, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function onSection() {
  if (currentSection.getType() != TYPE_TURNING) {
    if (!hasParameter("operation-strategy") || (getParameter("operation-strategy") != "drill")) {
      if (currentSection.getType() == TYPE_MILLING) {
        error(localize("Milling toolpath is not supported."));
      } else {
        error(localize("Non-turning toolpath is not supported."));
      }
      return;
    }
  }

  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  var retracted = false; // specifies that the tool has been retracted to the safe plane

  if (insertToolCall) {      
    // retract to safe plane

    /*    
    Q: Sequence – default: 0
    0: Diagonal path of traverse
    1: First in X axis, then in Z
    2: First in Z axis, then in X
    3: X axis only
    4: Z axis only
    */
    
    retracted = true;
    writeBlock(gFormat.format(14)); // retract
    forceXYZ();
  }
  
  if (insertToolCall) {
    retracted = true;
    onCommand(COMMAND_COOLANT_OFF);
  
    if (!isFirstSection() && properties.optionalStop) {
      onCommand(COMMAND_OPTIONAL_STOP);
    }

    if (tool.number > 99) {
      warning(localize("Tool number exceeds maximum value."));
    }

    if (tool.compensationOffset > 99) {
      error(localize("Compensation offset is out of range."));
      return;
    }
    writeBlock("T" + toolFormat.format(tool.number * 100 + tool.compensationOffset));
    if (tool.comment) {
      writeComment(tool.comment);
    }

    if (properties.preloadTool) {
      var nextTool = getNextTool(tool.number);
      if (nextTool) {
        if (nextTool.compensationOffset > 99) {
          error(localize("Compensation offset is out of range."));
          return;
        }
        writeBlock("T" + toolFormat.format(nextTool.number * 100 + nextTool.compensationOffset));
      } else {
        // preload first tool
        var section = getSection(0);
        var firstTool = section.getTool().number;
        if (tool.number != firstTool.number) {
          if (firstTool.compensationOffset > 99) {
            error(localize("Compensation offset is out of range."));
            return;
          }
          writeBlock("T" + toolFormat.format(firstTool.number * 100 + firstTool.compensationOffset));
        }
      }
    }
  }

  // wcs
  var workOffset = currentSection.workOffset;

  forceXYZ();

  // set coolant after we have positioned at Z
  {
    var c = mapCoolantTable.lookup(tool.coolant);
    if (c) {
      writeBlock(mFormat.format(c));
    } else {
      warning(localize("Coolant not supported."));
    }
  }

  forceAny();
  gMotionModal.reset();

  gFeedModeModal.reset();
  if (currentSection.feedMode == FEED_PER_REVOLUTION) {
    writeBlock(gFeedModeModal.format(95));
  } else {
    writeBlock(gFeedModeModal.format(94));
  }

  // writeBlock(mFormat.format(currentSection.tailstock ? x : x));
  // writeBlock(mFormat.format(clampPrimaryChuck ? x : x));
  // writeBlock(mFormat.format(clampSecondaryChuck ? x : x));
  
  gSpindleModeModal.reset();
  
  var mSpindle = tool.clockwise ? 3 : 4; // both primary and secondary
  if (currentSection.getTool().getSpindleMode() == SPINDLE_CONSTANT_SURFACE_SPEED) {
    writeBlock(gSpindleModeModal.format(96), sOutput.format(tool.surfaceSpeed * ((unit == MM) ? 1 : 1/12.0)), mFormat.format(mSpindle));
  } else {
    writeBlock(gSpindleModeModal.format(97), sOutput.format(tool.spindleRPM), mFormat.format(mSpindle));
  }
  // wait for spindle here
  
  setRotation(currentSection.workPlane);

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    // TAG: need to retract along X or Z
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
    }
  }

  if (insertToolCall) {

    gMotionModal.reset();
    
    writeBlock(
      gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), zOutput.format(initialPosition.z)
    );

    gMotionModal.reset();
  }
}

function onDwell(seconds) {
  if (seconds >= 999) {
    warning(localize("Dwelling time is out of range."));
  }
  writeBlock(gFormat.format(4), "F" + secFormat.format(seconds));
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      var d = tool.diameterOffset;
      if (d > 99) {
        warning(localize("The diameter offset exceeds the maximum value."));
      }
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        writeBlock(gMotionModal.format(0), gFormat.format(41), x, y, z, dOutput.format(d));
        break;
      case RADIUS_COMPENSATION_RIGHT:
        writeBlock(gMotionModal.format(0), gFormat.format(42), x, y, z, dOutput.format(d));
        break;
      default:
        writeBlock(gMotionModal.format(0), gFormat.format(40), x, y, z);
      }
    } else {
      writeBlock(gMotionModal.format(0), x, y, z);
    }
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      var d = tool.diameterOffset;
      if (d > 99) {
        warning(localize("The diameter offset exceeds the maximum value."));
      }
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        writeBlock(gMotionModal.format(1), gFormat.format(41), x, y, z, dOutput.format(d), f);
        break;
      case RADIUS_COMPENSATION_RIGHT:
        writeBlock(gMotionModal.format(1), gFormat.format(42), x, y, z, dOutput.format(d), f);
        break;
      default:
        writeBlock(gMotionModal.format(1), gFormat.format(40), x, y, z, f);
      }
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  if (isFullCircle()) {
    if (properties.useRadius || isHelical()) { // radius mode does not support full arcs
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gMotionModal.format(clockwise ? 12 : 13), iOutput.format(cx), kOutput.format(cz), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else if (!properties.useRadius) {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gMotionModal.format(clockwise ? 12 : 13), xOutput.format(y), zOutput.format(x), iOutput.format(cx), kOutput.format(cz), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else { // use radius mode
    var r = getCircularRadius();
    if (toDeg(getCircularSweep()) > (180 + 1e-9)) {
      r = -r; // allow up to <360 deg arcs
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gMotionModal.format(clockwise ? 12 : 13), xOutput.format(y), zOutput.format(x), "R" + rFormat.format(r), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  }
}

function onCycle() {
}

function getCommonCycle(x, y, z, r) {
  return [//xOutput.format(x), yOutput.format(y),
    zOutput.format(z),
    "R" + zFormat.format(r)];
}

function onCyclePoint(x, y, z) {
  if (isFirstCyclePoint()) {
    repositionToCycleClearance(cycle, x, y, z);
    
    // return to initial Z which is clearance plane and set absolute mode

    var F = cycle.feedrate;
    var E = (cycle.dwell == 0) ? 0 : clamp(0.001, cycle.dwell, 999.99999); // in seconds

    switch (cycleType) {
    case "drilling":
      writeBlock(
        gCycleModal.format(71),
        getCommonCycle(x, y, z, cycle.retract),
        feedOutput.format(F)
      );
      break;
    case "counter-boring":
      if (E > 0) {
        writeBlock(
          gCycleModal.format(71),
          getCommonCycle(x, y, z, cycle.retract),
          "E" + secFormat.format(E),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gCycleModal.format(71),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "chip-breaking":
      /*
      P: 1st drilling depth – default: Drill in one operation
      I: Reduction value – default: 0
      B: Return distance – default: Retract to“starting point of hole“
      J: Minimum hole depth – default: 1/10 of P
      */

      // cycle.accumulatedDepth is ignored
      writeBlock(
        gCycleModal.format(74),
        getCommonCycle(x, y, z, cycle.retract),
        "Q" + xFormat.format(cycle.incrementalDepth),
        conditional(E > 0, "E" + secFormat.format(E)),
        feedOutput.format(F)
      );
      break;
    case "deep-drilling":
      /*
      P: 1st drilling depth – default: Drill in one operation
      I: Reduction value – default: 0
      B: Return distance – default: Retract to“starting point of hole“
      J: Minimum hole depth – default: 1/10 of P
      */
      
      writeBlock(
        gCycleModal.format(74),
        getCommonCycle(x, y, z, cycle.retract),
        "Q" + xFormat.format(cycle.incrementalDepth),
        conditional(E > 0, "E" + secFormat.format(E)),
        feedOutput.format(F)
      );
      break;
    case "tapping":
      writeBlock(
        gCycleModal.format(36),
        getCommonCycle(x, y, z, cycle.retract),
        zFormat.format(tool.getThreadPitch()),
        "Q0",
        "H0"
      );
      break;
    case "left-tapping":
      writeBlock(
        gCycleModal.format(36),
        getCommonCycle(x, y, z, cycle.retract),
        zFormat.format(tool.getThreadPitch()),
        "Q0",
        "H0"
      );
      break;
    case "right-tapping":
      writeBlock(
        gCycleModal.format(36),
        getCommonCycle(x, y, z, cycle.retract),
        zFormat.format(tool.getThreadPitch()),
        "Q0",
        "H0"
      );
      break;
    default:
      expandCyclePoint(x, y, z);
    }
  } else {
    if (cycleExpanded) {
      expandCyclePoint(x, y, z);
    } else {
      writeBlock(yOutput.format(y));
    }
  }
}

function onCycleEnd() {
  if (!cycleExpanded) {
    writeBlock(gCycleModal.format(80));
    zOutput.reset();
  }
}

var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_OPTIONAL_STOP:1,
  COMMAND_END:2,
  COMMAND_SPINDLE_CLOCKWISE:3,
  COMMAND_SPINDLE_COUNTERCLOCKWISE:4,
  COMMAND_STOP_SPINDLE:5,
  COMMAND_COOLANT_ON:8,
  COMMAND_COOLANT_OFF:9
};

function onCommand(command) {
  switch (command) {
  case COMMAND_START_SPINDLE:
    onCommand(tool.clockwise ? COMMAND_SPINDLE_CLOCKWISE : COMMAND_SPINDLE_COUNTERCLOCKWISE);
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  forceAny();
}

function onClose() {
  onCommand(COMMAND_COOLANT_OFF);

  /*    
  Q: Sequence – default: 0
  0: Diagonal path of traverse
  1: First in X axis, then in Z
  2: First in Z axis, then in X
  3: X axis only
  4: Z axis only
  */

  writeBlock(gFormat.format(14)); // retract

  onImpliedCommand(COMMAND_END);
  onImpliedCommand(COMMAND_STOP_SPINDLE);
  writeBlock(mFormat.format(30)); // stop program, spindle stop, coolant off
  writeln("%");
}
