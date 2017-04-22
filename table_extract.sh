#!/bin/bash

if [ -z $1 ];then
        echo "no filename given";
        exit 1;
fi


if [ -z $2 ];then
        echo "no tablename given";
        exit 2;
fi


searched=$(ionice -c3 nice -n +19 gzip -d -c $1 | egrep -n '^-- Table structure for table ' | egrep -m1 -A1 "\`$2\`" | head -2 | cut -d ":" -f1 | xargs -n2)

BEGIN=`echo $searched | cut -d " " -f1`
END2=`echo $searched | cut -d " " -f2`
END=$((END2 -2))
echo $BEGIN $END $END2 >2
ionice -c3 nice -n +19 gzip -d -c $1 | sed -n "${BEGIN},${END}p;${END2}q"
