--- sorttable.js	2012-10-15 21:11:14.000000000 +0200
+++ sorttable2.js	2017-05-25 23:17:09.016817377 +0200
@@ -151,6 +151,8 @@
 	        //sorttable.shaker_sort(row_array, this.sorttable_sortfunction);
 	        /* and comment out this one */
 	        row_array.sort(this.sorttable_sortfunction);
+		// pgCluu: Sort in descending order first
+		row_array.reverse();
 
 	        tb = this.sorttable_tbody;
 	        for (var j=0; j<row_array.length; j++) {
@@ -169,7 +171,7 @@
     for (var i=0; i<table.tBodies[0].rows.length; i++) {
       text = sorttable.getInnerText(table.tBodies[0].rows[i].cells[column]);
       if (text != '') {
-        if (text.match(/^-?[£$¤]?[\d,.]+%?$/)) {
+        if (text.match(/^-?[Â£$Â¤]?[\d,.]+\s*[%KMGTP]?[B]?$/)) {
           return sorttable.sort_numeric;
         }
         // check for a date: dd/mm/yyyy or dd/mm/yy
@@ -259,15 +261,52 @@
      each sort function takes two parameters, a and b
      you are comparing a[0] and b[0] */
   sort_numeric: function(a,b) {
+    am = 1;
+    if (a[0].match(/KB/)) {
+	am = 1000;
+    } else if (a[0].match(/MB/)) {
+	am = 1000000;
+    } else if (a[0].match(/GB/)) {
+	am = 1000000000;
+    } else if (a[0].match(/TB/)) {
+	am = 1000000000000;
+    } else if (a[0].match(/PB/)) {
+	am = 1000000000000000;
+    }
     aa = parseFloat(a[0].replace(/[^0-9.-]/g,''));
     if (isNaN(aa)) aa = 0;
+    aa = aa*am;
+    bm = 1;
+    if (b[0].match(/KB/)) {
+	bm = 1000;
+    } else if (b[0].match(/MB/)) {
+	bm = 1000000;
+    } else if (b[0].match(/GB/)) {
+	bm = 1000000000;
+    } else if (b[0].match(/TB/)) {
+	bm = 1000000000000;
+    } else if (b[0].match(/PB/)) {
+	bm = 1000000000000000;
+    }
     bb = parseFloat(b[0].replace(/[^0-9.-]/g,''));
     if (isNaN(bb)) bb = 0;
+    bb = bb*bm;
+
     return aa-bb;
   },
   sort_alpha: function(a,b) {
-    if (a[0]==b[0]) return 0;
-    if (a[0]<b[0]) return -1;
+    // PgCluu: remove percentage for numeric sort
+    if (a[0].replace(/ <.*\(.*%\).*/, '')) {
+	b[0].replace(/ <.*\(.*%\).*/,''); 
+	aa = parseFloat(a[0].replace(/[^0-9.-]/g,''));
+	if (isNaN(aa)) aa = 0;
+	bb = parseFloat(b[0].replace(/[^0-9.-]/g,'')); 
+	if (isNaN(bb)) bb = 0;
+	return aa-bb;
+    } else {
+	if (a[0]==b[0]) return 0;
+	if (a[0]<b[0]) return -1;
+    }
     return 1;
   },
   sort_ddmm: function(a,b) {
