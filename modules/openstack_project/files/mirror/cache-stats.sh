#!/bin/bash
for X in /var/log/apache2/${HOSTNAME}*_access.log ; do
    HITS=$(grep ' cache hit ' ${X} | wc -l)
    REFRESHES=$(grep ' conditional cache hit: entity refreshed ' ${X} | wc -l)
    MISSES=$(grep ' cache miss: ' ${X} | wc -l)

    echo "${X}"
    echo "Cache Hits: $HITS"
    echo "Cache Refresshes: $REFRESHES"
    echo "Cache Misses: $MISSES"
    echo ""
done
