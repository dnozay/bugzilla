YUI.add("gallery-funcprog",function(e,t){"use strict";function n(t,n){var r=e.Array(arguments,1,!0);switch(e.Array.test(n)){case 1:return e.Array[t].apply(null,r);case 2:return r[0]=e.Array(n,0,!0),e.Array[t].apply(null,r);default:return n&&n[t]&&n!==e?(r.shift(),n[t].apply(n,r)):e.Object[t].apply(null,r)}}e.mix(e,{every:function(e,t,r,i){return n("every",e,t,r,i)},filter:function(e,t,r,i){return n("filter",e,t,r,i)},find:function(e,t,r,i){return n("find",e,t,r,i)},map:function(e,t,r,i){return n("map",e,t,r,i)},partition:function(e,t,r,i){return n("partition",e,t,r,i)},reduce:function(e,t,r,i,s){return n("reduce",e,t,r,i,s)},reduceRight:function(e,t,r,i,s){return n("reduceRight",e,t,r,i,s)},reject:function(e,t,r,i){return n("reject",e,t,r,i)}}),e.mix(e.Array,{findIndexOf:function(t,n,r){var i=-1;return e.Array.some(t,function(e,s){if(n.call(r,e,s,t))return i=s,!0}),i}}),e.Array.reduceRight=e.Lang._isNative(Array.prototype.reduceRight)?function(e,t,n,r){return Array.prototype.reduceRight.call(e,function(e,t,i,s){return n.call(r,e,t,i,s)},t)}:function(e,t,n,r){var i=t;for(var s=e.length-1;s>=0;s--)i=n.call(r,i,e[s],s,e);return i}},"@VERSION@",{requires:["oop","array-extras","gallery-object-extras"],optional:["gallery-nodelist-extras2"]});
