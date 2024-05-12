#!/usr/bin/env python3

import argparse
import os
import sys
import time

from datetime import datetime
from dateutil import parser as duparser
from kafka import KafkaConsumer
from kafka.structs import TopicPartition

DEFAULT_COUNT = 1000
DEFAULT_MAX = 1048576

now = datetime.now().timestamp()
parser = argparse.ArgumentParser()

parser.add_argument('--begin', '-b')
parser.add_argument('--end', '-e')
parser.add_argument('--start', '-s', type=int)
parser.add_argument('--count', '-c', default=-1, type=int)
parser.add_argument('--bootstrap', '-k', action='append', required=True)
parser.add_argument('--group', '-g', default='exporthub')
parser.add_argument('--topic', '-t', default='DistributionTopic')
parser.add_argument('--print', '-p', action='store_true')
parser.add_argument('--dir', '-d', default='.')
parser.add_argument('--format' , '-f', default='record_%09d.json')
parser.add_argument('--nofilter', '-n', action='store_true')
parser.add_argument('--max', '-m', type=int, default=DEFAULT_MAX)

args = parser.parse_args()

if not os.path.isdir(args.dir):
    print('%s is not a directory' % args.dir)
    sys.exit(1)

consumer = KafkaConsumer(group_id=args.group,
                         bootstrap_servers=args.bootstrap,
                         enable_auto_commit=False,
                         auto_offset_reset='earliest',
                         max_partition_fetch_bytes=max(args.max, DEFAULT_MAX))
partitions = consumer.partitions_for_topic(args.topic)

if (len(partitions) < 1):
    print("topic %s has no partitions" % args.topic)
    sys.exit(1)

t = TopicPartition(args.topic, partitions.pop())
consumer.assign([t])

beginOffset = consumer.beginning_offsets([t])[t]
endOffset = consumer.end_offsets([t])[t]
beginTime = None
endTime = None
startPosition = beginOffset

if args.start:
    if args.begin:
        print('You cannot specify start offset and begin time')
        sys.exit(1)
    if args.end and args.count > 0:
        print('Too many options')
        sys.exit(1)
    startPosition = args.start

if args.begin:
    beginTime = duparser.parse(args.begin).timestamp()
    if args.end and args.count > 0:
        print('Too many options')
        sys.exit(1)

if args.end:
    if args.end == 'now':
        endTime = now
    else:
        endTime = duparser.parse(args.end).timestamp()

if beginTime:
    offtime = consumer.offsets_for_times({t: beginTime * 1000})[t]
    if offtime:
        startPosition = offtime.offset
    else:
        print('No offset timestamps after begin time')
        sys.exit(1)

startPosition = max(startPosition, beginOffset)

if endTime:
    offtime = consumer.offsets_for_times({t: endTime * 1000})[t]
    if offtime:
        endPosition = offtime.offset
    else:
        endPosition = endOffset
    if args.count > 0:
        startPosition = endPosition - args.count
    elif not beginTime and not args.start:
        startPosition = endPosition - DEFAULT_COUNT
else:
    if args.count > 0:
        endPosition = startPosition + args.count
    else:
        endPosition = startPosition + DEFAULT_COUNT

endPosition = min(endPosition, endOffset)

if args.print:
    print("begin %d end %d" % (startPosition, endPosition))    
else:
    print("Saving records in range %d - %d to %s" % (startPosition, endPosition, args.dir), flush=True)

recordCount = 0
for x in range(startPosition, endPosition):
    consumer.seek(t, x)
    record = consumer.poll(max_records=1, update_offsets=False, timeout_ms=1000)[t][0]
    patch = record.value.decode('utf-8')
    recordCount += 1
    filename = os.path.join(args.dir, (args.format % record.offset))
    if (not args.nofilter and patch.find('@type') < 0):
        if (not args.print and recordCount % 10000 == 0):
            print("%d: %s" % (recordCount, filename), flush=True) 
        continue
    if (args.print):
        print("offset %d time %s size %d\n%s" % (record.offset, datetime.fromtimestamp(record.timestamp / 1000), record.serialized_value_size, patch))
    else:
        open(filename, "w").write(patch)
        if (recordCount % 10000 == 0):
            print("%d: %s" % (recordCount, filename), flush=True)

print('Done')
consumer.close()
