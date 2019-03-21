
/* <![CDATA[ */

function create_download_button (buttonid, cssclass) {
	document.writeln('<button type="button" id="download'+buttonid+'" class="btn btn-danger" data-toggle="modal" data-target="#pgcluuModal">Download</button>');
	document.writeln('<button type="button" id="csv'+buttonid+'" class="btn btn-danger" >CSV export</button>');
	document.writeln('<a id="acsv'+buttonid+'" href="#"></a>');
}

/* Disable disabled menus */
$(document).ready(function() {
   $(".nav li.disabled a").click(function() {
     return false;
   });
});

function add_download_button_event (buttonid, divid, plot) {

	jQuery('#download'+buttonid).click( function() {
		$('#pgcluuModal img').attr('src', $('#'+divid).jqplotToImageStr({}));
	});
	jQuery('#csv'+buttonid).click( function() {
		export_csv(plot, buttonid);
	});

}

function create_linegraph (divid, charttitle, ylabel, arr_series, lineseries, y2label) {
        return $.jqplot(divid, lineseries, { 
        seriesColors: ['#6e9dc9','#f4ab3a','#ac7fa8','#8dbd0f',"#958c12","#953579", "#4b5de4", "#d8b83f", "#ff5800", "#0085cc"],
        seriesDefaults: { markerOptions: {show: false}, lineWidth:1 },
        grid: { borderWidth: 1, background: '#ffffff'},
        title: charttitle,
        series: arr_series,
        axes: {
            xaxis: {
                renderer:$.jqplot.DateAxisRenderer,
                tickOptions:{ angle: -30, textColor: '#333' },
            },
            yaxis: {
		label: ylabel,
                renderer: $.jqplot.LogAxisRenderer,
                labelRenderer: $.jqplot.CanvasAxisLabelRenderer,
                tickRenderer: $.jqplot.CanvasAxisTickRenderer,
                tickOptions: {
                        textColor: '#333',
                        formatter: function(format, value) { return pretty_print_number(value, 0, ylabel); }
                },
            }
        },
        legend: {
            show: true,
	    placement: 'outside',
	    location:'e'
        },
        cursor:{
            show: true,
            zoom: true,
            showTooltip:false,
            looseZoom: true,
            followMouse: true,
        },
        highlighter: {
                show: true,
                tooltipContentEditor: function (str, seriesIndex, pointIndex, plot) {
                    var dateToDisplay = new Date(plot.data[seriesIndex][pointIndex][0]);
                    var textToShow = '<div>On '+dateToDisplay.toString().substring(0,33)+'<br>'+dateToDisplay.toString().substring(34);
                    for (var i=0; i<plot.data.length;i++) {
                            textToShow += '<br><span class="mfigure">'+pretty_print_number(plot.data[i][pointIndex][1], 2, plot.series[i].label)+' <small>'+plot.series[i].label+'</small></span>';
                    }
                    textToShow += '</div>';
                    return textToShow;
                }
        }
    });
}

function create_piechart(divid, title, data) {
	return $.jqplot(divid, [data], 
	{
		seriesColors: ['#6e9dc9','#f4ab3a','#ac7fa8','#8dbd0f',"#958c12","#953579", "#4b5de4", "#d8b83f", "#ff5800", "#0085cc","#4bb2c5", "#c5b47f", "#EAA228", "#579575", "#839557","#498991", "#C08840", "#9F9274", "#546D61", "#646C4A", "#6F6621","#6E3F5F", "#4F64B0", "#A89050", "#C45923", "#187399", "#945381","#959E5C", "#C7AF7B", "#478396", "#907294"],
		grid: { borderWidth: 1, background: '#ffffff'},
		title: title,
		seriesDefaults: {
			renderer: $.jqplot.PieRenderer,
			rendererOptions: {
				showDataLabels: true
			}
		}, 
		legend: { show:true, location: 'e' },
		highlighter: {
			show: true,
			tooltipLocation:'sw', 
			useAxesFormatters:false,
			tooltipContentEditor: function (str, seriesIndex, pointIndex, plot) {
			    var textToShow = '<div>';
			    //textToShow += '<span class="mfigure">'+pretty_print_number(plot.data[0][pointIndex][1], 2)+' <small>'+plot.data[0][pointIndex][0]+'</small></span>';
			    textToShow += '<span class="mfigure">'+format_number(plot.data[0][pointIndex][1])+' <small>'+plot.data[0][pointIndex][0]+'</small></span>';
			    textToShow += '</div>';
			    return textToShow;
			}
		}
	}
	);
}

function create_bargraph (divid, title, ytitle, data, y2title) {
	return $.jqplot(divid, data, {
		grid: { borderWidth: 1, background: '#ffffff'},
		title: title,
		seriesDefaults: {
			rendererOptions: {
				barPadding: 4,
				barMargin: 5,
			}
		},
		seriesColors: ['#6e9dc9','#8dbd0f','#f4ab3a','#ac7fa8',"#958c12","#953579", "#4b5de4", "#d8b83f", "#ff5800", "#0085cc"],
		series:[
			{ renderer:$.jqplot.BarRenderer, label: ytitle},
			{ yaxis:'y2axis', label: y2title, markerOptions: {show: false}, lineWidth:1 }
		],
		axes: {
		    xaxis: {
			renderer: $.jqplot.CategoryAxisRenderer, 
			drawMajorGridlines: false,
			drawMajorTickMarks: false,
			tickRenderer: $.jqplot.CanvasAxisTickRenderer,
			tickOptions: {
			    angle: -30,
			    textColor: '#333',
			    formatString:'%H:%M',
			    fontFamily:'Helvetica',
			    fontSize: '8pt'
			}
		    },
		    yaxis: {
			autoscale:true,
			labelRenderer: $.jqplot.CanvasAxisLabelRenderer,
			tickOptions:{ textColor: '#333' },
			tickRenderer: $.jqplot.CanvasAxisTickRenderer,
                        tickOptions: {
                            textColor: '#333',
                            formatter: function(format, value) { return pretty_print_number(value, 0, ytitle); },
			    fontFamily:'Helvetica',
			    fontSize: '8pt'
                        },
			label: ytitle
		    },
		    y2axis: {
			autoscale:true,
			labelRenderer: $.jqplot.CanvasAxisLabelRenderer,
			tickRenderer: $.jqplot.CanvasAxisTickRenderer,
			tickOptions: {
			    textColor: '#8dbd0f',
			    formatter: function(format, value) { return pretty_print_number(value, 0, y2title); },
			    fontFamily:'Helvetica',
			    fontSize: '8pt'
			},
                        rendererOptions: {
                                alignTicks: true,
                        },
			label: y2title,
			
		    }
		},
		highlighter: {
			show: true,
			tooltipLocation:'ne', 
			useAxesFormatters:false,
			tooltipContentEditor: function (str, seriesIndex, pointIndex, plot) {
			    var textToShow = '<div style="z-index: 99;">At '+plot.data[0][pointIndex][0];
			    for (var i=0; i<plot.data.length;i++) {
				    textToShow += '<br><span class="mfigure">'+pretty_print_number(plot.data[i][pointIndex][1], 2, plot.series[i].label)+' <small>'+plot.series[i].label+'</small></span>';
			    }
			    textToShow += '</div>';
			    return textToShow;
			}
		}
	});
}

function pretty_print_number(val, scale, type) 
{

	if ( (scale == undefined) || ((scale == 0) && (val != 0)) ) {
		scale = 1;
	};

	if (type != undefined) {
		type = type.toLowerCase();

		if (type.search('size') >= 0) {
			if (Math.abs(val) >= 1125899906842624) {
				val = (val / 1125899906842624);
				return val.toFixed(scale) + " PiB";
			} else if (Math.abs(val) >= 1099511627776) {
				val = (val / 1099511627776);
				return val.toFixed(scale) + " TiB";
			} else if (Math.abs(val) >= 1073741824) {
				val = (val / 1073741824);
				return val.toFixed(scale) + " GiB";
			} else if (Math.abs(val) >= 1048576) {
				val = (val / 1048576);
				return val.toFixed(scale) + " MiB";
			} else if (Math.abs(val) >= 1024) {
				val = (val / 1024);
				return val.toFixed(scale) + " KiB";
			} else {
				return val.toFixed(scale) + " B";
			}
		} else if (type.search('duration') >= 0) {
			if (Math.abs(val) >= 1000) {
				val = (val / 1000);
				return val.toFixed(scale) + " sec";
			} else {
				return val + " ms";
			}
		} else {
			if (Math.abs(val) >= 1000000000000000) {
				val = (val / 1000000000000000);
				return val.toFixed(scale) + " P";
			} else if (Math.abs(val) >= 1000000000000) {
				val = (val / 1000000000000);
				return val.toFixed(scale) + " T";
			} else if (Math.abs(val) >= 1000000000) {
				val = (val / 1000000000);
				return val.toFixed(scale) + " G";
			} else if (Math.abs(val) >= 1000000) {
				val = (val / 1000000);
				return val.toFixed(scale) + " M";
			} else if (Math.abs(val) >= 1000) {
				val = (val / 1000);
				return val.toFixed(scale) + " K";
			}
		}
	}

	return val.toFixed(scale);
}

function format_number(val) {
        var decimal = 2;
        var msep = ',';
        var deci = Math.round( Math.pow(10,decimal)*(Math.abs(val)-Math.floor(Math.abs(val)))) ;     
        val = Math.floor(Math.abs(val));
        if ((decimal==0)||(deci==Math.pow(10,decimal))) {deci=0;}
        var val_format=val+""; 
        var nb=val_format.length;
        for (var i=1;i<4;i++) {
                if (val>=Math.pow(10,(3*i))) {
                        val_format=val_format.substring(0,nb-(3*i))+msep+val_format.substring(nb-(3*i));
                }       
        }       
        if (decimal>0) {
                var decim="";
                for (var j=0;j<(decimal-deci.toString().length);j++) {decim+="0";}
                deci=decim+deci.toString();
		if (deci > 0) {
			val_format=val_format+"."+deci;
		}
        }
        if (parseFloat(val)<0) {val_format="-"+val_format;}
        return val_format;
}

function export_csv(plot, buttonid) {

  if (jQuery('#acsv' + buttonid).attr('href') == '#') {
    var csv = "data:text/csv;charset=utf-8,";

    if (plot.seriesDefaults != null) {
      csv += '"serie","epoch","value"\n';
    } else {
      csv += '"serie","value"\n';
    }
    _.each(plot.series[0]._plotValues.x, function(val,i) {
      _.each(plot.series, function(s, j) {
        if (plot.plugins.lineRenderer != null) {
          csv += '"' + s.label + '",' + s._plotValues.x[i] + ',' + s._plotValues.y[i] + '\n';
        }
        else {
          csv += '"' + s._plotValues.x[i] + '",' + s._plotValues.y[i] + '\n';
        }
      });
    });

    var encodedUri = encodeURI(csv);
    jQuery('#acsv' + buttonid).attr('href', encodedUri).attr('download', 'data.csv');
  }

  document.getElementById('acsv' + buttonid).click();
}
