// Fonts
var fontLink = document.createElement("link");
fontLink.href = "https://fonts.googleapis.com/css2?family=Oswald:wght@400;700&family=Merriweather:ital,wght@0,300;0,700;1,300&display=swap";
fontLink.rel = "stylesheet";
document.head.appendChild(fontLink);

svg.selectAll("*").remove();

var width = width;
var height = height;
var margin = {top: 60, right: 60, bottom: 60, left: 60};

// Description text location
var chartWidth = width * .8;
var textX = chartWidth/2;

// Layers
var bgLayer = svg.append("g").attr("class", "bg-layer");
var axisLayer = svg.append("g").attr("class", "axis-layer");
var dotLayer = svg.append("g").attr("class", "dot-layer");
var uiLayer = svg.append("g").attr("class", "ui-layer");

// Scales for Plotting
// Stacking Positions, and Lead Concentration
var maxLead = d3.max(data, d => d.lead);
var maxStack = d3.max(data, d => d.stack_pos);

var xScale = d3.scaleLinear()
    .domain([0, maxLead])
    .range([margin.left, chartWidth]);

var yScale = d3.scaleLinear()
    .domain([0, maxStack + 4]) 
    .range([height - margin.bottom, margin.top]);

// Droplet Colours
var colorScale = d3.scaleLinear()
    .domain([0, 5, 15, 50])
    .range(["#3498db", "#f1c40f", "#e67e22", "#c0392b"]);

// Text engine
// container for text inside the SVG
var headline = uiLayer.append("text")
    .attr("x", textX)
    .attr("y", margin.top + 40)
    .style("font-family", "'Oswald', sans-serif")
    .style("font-size", "42px")
    .style("font-weight", "700")
    .style("fill", "#2c3e50")
    .style("opacity", 0);

var bodyText = uiLayer.append("text")
    .attr("x", textX)
    .attr("y", margin.top + 90)
    .style("font-family", "'Merriweather', serif")
    .style("font-size", "15px")
    .style("fill", "#555")
    .style("opacity", 0);

// update text within transition
function updateText(head, bodyLines) {
    // disppear
    headline.transition().duration(500).style("opacity", 0);
    bodyText.transition().duration(500).style("opacity", 0)
        .on("end", function() {
            // update content
            headline.text(head);
            
            bodyText.selectAll("tspan").remove();
            bodyLines.forEach((line, i) => {
                bodyText.append("tspan")
                    .attr("x", textX)
                    .attr("dy", "1.6em")
                    .text(line);
            });
            
            // other text appear
            headline.transition().duration(800).style("opacity", 1);
            bodyText.transition().duration(800).style("opacity", 1);
        });
}

// next chapter buttom
var btnGroup = uiLayer.append("g")
    .attr("transform", `translate(${width - 150}, ${height - 50})`)
    .style("cursor", "pointer")
    .on("click", () => {
        step = (step + 1) % 7;
        if(step === 0) {
            resetVisualization();
        } else {
            drawStep(step);
        }
    });

btnGroup.append("rect")
    .attr("width", 140).attr("height", 45).attr("rx", 4)
    .attr("fill", "#e74c3c")
    .style("box-shadow", "2px 2px 5px rgba(0,0,0,0.2)");

btnGroup.append("text")
    .attr("x", 70).attr("y", 28).attr("text-anchor", "middle")
    .text("Click for Next Frame")
    .style("font-family", "'Oswald', sans-serif").style("fill", "white").style("font-size", "14px");

// forming axis
var xAxis = d3.axisBottom(xScale).ticks(10);
axisLayer.append("g").attr("transform", `translate(0, ${height - margin.bottom})`).call(xAxis);
axisLayer.append("text").attr("x", chartWidth/2).attr("y", height - 15).style("text-anchor", "middle")
    .style("font-family", "sans-serif").style("font-size", "12px").style("fill", "#aaa").text("Lead Concentration (ppb)");

// Droplet Shape
function getDropletPath(w) {
    var h = w * 1.5; var r = w / 2;
    return `M 0,0 C ${-r},0 ${-w},${-r} 0,${-h} C ${w},${-r} ${r},0 0,0 Z`;
}


// Animations

// initialised dots / hidden up at the top
var dots = dotLayer.selectAll("path")
    .data(data).enter().append("path")
    .attr("d", getDropletPath(6))
    .attr("transform", d => `translate(${xScale(d.lead_bin)}, -200)`) // Start way above
    .attr("fill", d => colorScale(d.lead))
    .style("opacity", 0);

// Line References
var refLines = { epa: null, epaText: null, q90: null, q90Text: null };

function updateLines(showEpa, q90Val, q90Label, q90Color) {
    // EPA Line
    if(showEpa && !refLines.epa) {
        refLines.epa = axisLayer.append("line")
            .attr("x1", xScale(15)).attr("x2", xScale(15))
            .attr("y1", height-margin.bottom).attr("y2", margin.top)
            .attr("stroke", "#c0392b").attr("stroke-width", 2).attr("stroke-dasharray", "6,4")
            .style("opacity", 0);
       refLines.epa.transition().duration(1000).style("opacity", 1);

       refLines.epaText = axisLayer.append("text")
          .attr("x", xScale(15)+5).attr("y", margin.top -5)
          .text("EPA LIMIT (15)").style("fill", "#c0392b").style("font-family", "Oswald").style("font-size", "12px")
          .style("opacity", 0);
       refLines.epaText.transition().style("opacity", 1);
    }

    // 90th Percentile Line
    if(q90Val !== null) {
        if(!refLines.q90) {
            // New line
            refLines.q90 = axisLayer.append("line")
                .attr("x1", xScale(q90Val)).attr("x2", xScale(q90Val))
                .attr("y1", height-margin.bottom).attr("y2", margin.top)
                .attr("stroke", q90Color).attr("stroke-width", 4)
                .style("opacity", 0);
            
            refLines.q90Text = axisLayer.append("text")
                .attr("x", xScale(q90Val)+8).attr("y", margin.top + 25)
                .style("font-family", "Oswald").style("font-weight", "bold").style("font-size", "18px")
                .style("fill", q90Color).style("opacity", 0);

            refLines.q90.transition().duration(1000).style("opacity", 1);
            refLines.q90Text.transition().duration(1000).style("opacity", 1).text(q90Label);
        } else {
            // update existing
            refLines.q90.transition().duration(1500)
                .attr("x1", xScale(q90Val)).attr("x2", xScale(q90Val))
                .attr("stroke", q90Color);

            refLines.q90Text.transition().duration(1500)
                .attr("x", xScale(q90Val)+8).style("fill", q90Color)
                .tween("text", function() {
                    // delay text update until line moves
                    var that = this; setTimeout(() => { d3.select(that).text(q90Label); }, 750);
                });
        }
    }
}

// Reset function to clear everything
function resetVisualization() {
    // Fade out all dots
    dots.transition().duration(800)
        .attr("transform", d => `translate(${xScale(d.lead_bin)}, -200)`)
        .style("opacity", 0)
        .on("end", function(d, i) {
            // Only call drawStep after the last dot finishes
            if(i === data.length - 1) {
                drawStep(0);
            }
        });
    
  // Fade out and remove reference lines
    if(refLines.epa) {
        refLines.epa.transition().duration(600).style("opacity", 0).remove();
        refLines.epa = null;
    }
    if(refLines.epaText) {
        refLines.epaText.transition().duration(600).style("opacity", 0).remove();
        refLines.epaText = null;
    }
    if(refLines.q90) {
        refLines.q90.transition().duration(600).style("opacity", 0).remove();
        refLines.q90 = null;
    }
    if(refLines.q90Text) {
        refLines.q90Text.transition().duration(600).style("opacity", 0).remove();
        refLines.q90Text = null;
    }
    
    // Fade out text immediately
    headline.transition().duration(400).style("opacity", 0);
    bodyText.transition().duration(400).style("opacity", 0);
}

// Story
var step = 0;
function drawStep(s) {
    if(s === 0) {
        // Intro
        updateText("THE CRISIS BEGINS", [
            "In 2015, residents of Flint reported",
            "foul-smelling, discoloured water.",
            "Officials insisted it was safe.",
            "Residents began testing it themselves."
        ]);
        dots.attr("transform", d => `translate(${xScale(d.lead_bin)}, -200)`).style("opacity", 0);
        if(refLines.epa) refLines.epa.style("opacity", 0);
    } 
    else if (s === 1) {
        // Collection of Samples
        updateText("THE SAMPLES", [
            "Hundreds of bottles flooded in.",
            "Each droplet here represents",
            "one home's water sample.",
            "Watch the distribution build."
        ]);
        
        // The Drizzle Effect
        dots.style("opacity", 0.9)
            .transition()
            .duration(1500) // fall time
            .delay((d, i) => i * 3) // staggered
            .ease(d3.easeBackOut.overshoot(1.36))
            .attr("transform", d => `translate(${xScale(d.lead_bin)}, ${yScale(d.stack_pos)})`);
    } 
    else if (s === 2) {
        // The Federal Limit
        updateText("THE FEDERAL LIMIT", [
            "The EPA sets the Action Level at 15 ppb.",
            "If the 90th percentile of samples",
            "exceeds this line, the city",
            "must take immediate action."
        ]);
        updateLines(true, null, null, null);
    } 
    else if (s === 3) {
        // Violation!
        updateText("A CLEAR VIOLATION", [
            "The initial calculation was damning.",
            "The 90th percentile was " + Math.round(options.q90_orig) + " ppb.",
            "This is well into the Danger Zone.",
            "Flint officials faced a crisis."
        ]);
        updateLines(true, options.q90_orig, Math.round(options.q90_orig) + " ppb", "#c0392b"); // RED
    } 
    else if (s === 4) {
        // MDEQ intervention
        updateText("THE MANIPULATION", [
            "MDEQ officials needed the number to be lower.",
            "They invalidated high-lead samples",
            "on technicalities, like Lee-Anne Walters'",
            "104 ppb sample (excluded for the usage of a filter')."
        ]);
        
        // Pulse Animation for removed dots
        dots.filter(d => d.is_removed)
            .transition().duration(300).attr("fill", "#000000").attr("d", getDropletPath(20))
            .transition().duration(300).attr("d", getDropletPath(6))
            .transition().duration(300).attr("fill", "#000000").attr("d", getDropletPath(20))
            .transition().duration(300).attr("d", getDropletPath(6));
    } 
    else if (s === 5) {
        // Removing data points
        updateText("AN ERASURE PROBLEM", [
            "By discarding the worst offenders,",
            "the dataset was fundamentally altered.",
            "Watch the removed samples vanish."
        ]);
        
        // Disappearing data points
        dots.filter(d => d.is_removed)
            .transition().duration(1500)
            .attr("transform", d => `translate(${xScale(d.lead_bin)}, -200)`)
            .style("opacity", 0);
            
        // Fade the kept samples slightly to emphasize the change
        dots.filter(d => !d.is_removed)
            .transition().duration(1000).attr("fill", d => colorScale(d.lead));
    } 
    else if (s === 6) {
        // Manufactured Result
        updateText("MANUFACTURED SAFETY", [
            "With the data manipulated,",
            "the 90th percentile slid to " + Math.round(options.q90_new) + " ppb.",
            "Just barely below the line.",
            "The water was declared 'Safe'."
        ]);
        
        // Slide line to Green
        updateLines(true, options.q90_new, Math.round(options.q90_new) + " ppb", "#27ae60"); // GREEN
    }
}

// Start
drawStep(0);