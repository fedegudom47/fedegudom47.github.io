var fontLink = document.createElement("link");
fontLink.href = "https://fonts.googleapis.com/css2?family=Exo+2:ital,wght@1,400;1,700;1,900&family=Roboto:wght@400;500&display=swap";
fontLink.rel = "stylesheet";
document.head.appendChild(fontLink);

svg.selectAll("*").remove();
d3.select("body").selectAll(".d3-tooltip").remove();

var width = width || 900;
var height = height || 600;

// Background: "Tarmac" (Neutral Dark Grey)
svg.append("rect").attr("width", width).attr("height", height).attr("fill", "#1e1e1e");

var mapLayer = svg.append("g").attr("class", "map-layer");
var gridLayer = svg.append("g").attr("class", "grid-layer");
var axisLayer = svg.append("g").attr("class", "axis-layer");
var bubbleLayer = svg.append("g").attr("class", "bubble-layer");
var uiLayer = svg.append("g").attr("class", "ui-layer");


// --- 2. SCALES & COLORS ---
function num(x) { return +x || 0; }

// Color Scale 1: Country of Origin
var countryColors = d3.scaleOrdinal(d3.schemeCategory10);

// Color Scale 2: Engine Type
var typeColors = d3.scaleOrdinal()
    .domain(["Petrol", "Diesel", "Hybrid", "Electric", "Sedan", "SUV"])
    .range([
         "#FF4D4D", // Petrol – bright red
        "#3A86FF", // Diesel – vivid blue
        "#2ECC71", // Hybrid – bright green
        "#00E5FF", // Electric – neon cyan
        "#BDC3FF", // Sedan – light lavender/gray
        "#FFB703"  // SUV – bright amber
    ]);

// Smaller Bubbles (3px to 12px)
var radiusScale = d3.scaleSqrt()
    .domain([0, d3.max(data, d => num(d.horsepower))])
    .range([3, 12]);
    
// Legend Container
var legendG = uiLayer.append("g")
    .attr("class", "legend-group")
    .attr("transform", `translate(30, ${height - 120})`);


// -- MAP COORDS --
var projection = d3.geoMercator()
    .scale(width / 6.5)
    .translate([width / 2, height / 1.6]);
var pathGenerator = d3.geoPath().projection(projection);

var countryCoords = {
    "Germany": [10.45, 51.16], "UK": [-3.43, 55.37], "Italy": [12.56, 41.87],
    "USA": [-95.71, 37.09], "Japan": [138.25, 36.20], "France": [2.21, 46.22],
    "Sweden": [18.64, 60.12], "China": [104.19, 35.86], "PR China": [104.19, 35.86],
    "Korea": [127.76, 35.90], "South Korea": [127.76, 35.90]
};

// -- GRID CALCULATIONS --
var numCols = 7; 
var rowHeight = 130;
var makes = [...new Set(data.map(d => d.make))].sort();
var gridCenters = {};

makes.forEach((make, i) => {
    var col = i % numCols;
    var row = Math.floor(i / numCols);
    gridCenters[make] = {
        x: (col * (width / numCols)) + (width / numCols / 2),
        y: (row * rowHeight) + 180,
        w: (width / numCols) - 10,
        h: rowHeight - 20
    };
});

// -- AXIS SCALES --
var performanceScale = d3.scaleLinear()
    .domain([d3.min(data,d=>num(d.performance)), d3.max(data,d=>num(d.performance))])
    .range([160, height - 50]);

var massScale = d3.scaleLinear().domain([d3.min(data,d=>num(d.mass)), d3.max(data,d=>num(d.mass))]).range([60, width-60]);
var hpScale = d3.scaleLinear().domain([0, d3.max(data,d=>num(d.horsepower))]).range([height-60, 160]);


// --- 3. UI (Speed Style) ---
var sceneTitle = uiLayer.append("text")
    .attr("x", width/2).attr("y", 50).attr("text-anchor", "middle")
    .style("font-family", "'Exo 2', sans-serif") 
    .style("font-style", "italic")
    .style("font-size", "48px").style("font-weight", "900")
    .style("fill", "#fff")
    .style("text-transform", "uppercase")
    .style("text-shadow", "2px 2px 0px #ff2400"); 

var storyText = uiLayer.append("text")
    .attr("x", width/2).attr("y", 85).attr("text-anchor", "middle")
    .style("font-family", "'Exo 2', sans-serif").style("font-style", "italic")
    .style("font-size", "16px").style("fill", "#ccc");

var btnNext = uiLayer.append("text")
    .attr("x", width-30).attr("y", height-30).attr("text-anchor", "end")
    .style("font-family", "'Exo 2'").style("font-style", "italic")
    .style("font-size", "20px").style("font-weight", "bold")
    .style("fill", "#ff2400").style("cursor", "pointer")
    .text("NEXT LAP >>");

var tooltip = d3.select("body").append("div").attr("class", "d3-tooltip")
    .style("position", "absolute").style("background", "white")
    .style("border-left", "5px solid #ff2400")
    .style("color", "#111")
    .style("padding", "10px").style("pointer-events", "none").style("opacity", 0)
    .style("font-family", "'Exo 2'").style("font-style", "italic")
    .style("font-size", "12px")
    .style("box-shadow", "4px 4px 10px rgba(0,0,0,0.5)");

// --- 4. MAP LOAD ---
d3.json("https://raw.githubusercontent.com/holtzy/D3-graph-gallery/master/DATA/world.geojson", function(error, mapData) {
    if(!error){
        mapLayer.selectAll("path").data(mapData.features).enter().append("path")
            .attr("d", pathGenerator)
            .attr("fill", "#2c3e50")
            .attr("stroke", "#34495e").attr("stroke-width", 1)
            .style("opacity", 0);
    }
    startSimulation();
});

// --- 5. SIMULATION ---
var simulation, nodes;

function startSimulation() {
    simulation = d3.forceSimulation()
        .nodes(data)
        .velocityDecay(0.6)
        .alphaDecay(0.01)
        .force('charge', d3.forceManyBody().strength(-15))
        .force('collide', d3.forceCollide().strength(1).radius(d => radiusScale(num(d.horsepower)) + 1))
        .on("tick", () => nodes.attr("cx", d => d.x).attr("cy", d => d.y));

    nodes = bubbleLayer.selectAll("circle")
        .data(data).enter().append("circle")
        .attr("cx", width/2).attr("cy", height/2)
        .attr("r", d => radiusScale(num(d.horsepower)))
        // FIX 1: Set initial color to Country (Origin)
        .attr("fill", d => countryColors(d.origin))
        .attr("stroke", "#1e1e1e").attr("stroke-width", 1.5).attr("opacity", 0.95)
        .on("mouseover", function(d) {
            d3.select(this).attr("stroke", "#fff").attr("stroke-width", 2).style("opacity", 1);
            tooltip.transition().duration(50).style("opacity", 1);
            tooltip.html(`
                <strong style="font-size:14px; text-transform:uppercase;">${d.make} ${d.model}</strong><br/>
                <span style="color:#ff2400">Origin:</span> ${d.origin}<br/>
                <span style="color:#ff2400">Type:</span> ${d.type || 'Petrol'}<br/>
                <div style="margin-top:5px; border-top:1px solid #eee; padding-top:5px;">
                HP: <strong>${d.horsepower}</strong> | PRICE: <strong>$${Math.round(num(d.price)).toLocaleString()}</strong>
                </div>
            `).style("left", (d3.event.pageX+15)+"px").style("top", (d3.event.pageY-28)+"px");
        })
        .on("mouseout", function() {
            d3.select(this).attr("stroke", "#1e1e1e").attr("stroke-width", 1.5).style("opacity", 0.95);
            tooltip.transition().duration(200).style("opacity", 0);
        });

    drawStep(0);
}

function drawLegend(scale, title) {
    legendG.selectAll("*").remove();
    
    legendG.append("text")
        .text(title.toUpperCase())
        .style("fill", "#fff").style("font-family", "'Exo 2'").style("font-weight", "900")
        .style("font-size", "12px").attr("y", -10);

    var keys = scale.domain();
    keys.forEach((key, i) => {
        var row = legendG.append("g").attr("transform", `translate(0, ${i * 20})`);
        row.append("rect").attr("width", 12).attr("height", 12).attr("fill", scale(key));
        row.append("text").attr("x", 20).attr("y", 10).text(key)
            .style("fill", "#ccc").style("font-family", "'Exo 2'").style("font-size", "11px");
    });
}

// --- 6. SCENE LOGIC ---
function drawStep(step) {
    // Reset visual noise
    axisLayer.selectAll("*").transition().duration(400).style("opacity", 0).remove();
    gridLayer.selectAll("*").transition().duration(400).style("opacity", 0).remove();
    mapLayer.selectAll("path").transition().duration(800).style("opacity", step === 0 ? 1 : 0.05);
    
    simulation.alpha(1).restart(); 

    // FIX 2: Handle Color Logic per Step
    if (step === 0) {
        // MAP SCENE: Color by COUNTRY
        updateUI("Global Origins", "Distributed by Country of Origin");
        drawLegend(countryColors, "Country of Origin");
        
        nodes.transition().duration(800)
            .attr("fill", d => countryColors(d.origin)); // Reset to country color

        simulation
            .force('x', d3.forceX().strength(0.25).x(d => {
                 var c = countryCoords[d.origin];
                 return c ? projection(c)[0] : width/2;
            }))
            .force('y', d3.forceY().strength(0.25).y(d => {
                 var c = countryCoords[d.origin];
                 return c ? projection(c)[1] : height/2;
            }));
    } 
    else {
        // ALL OTHER SCENES: Color by TYPE
        updateUI("Analysis Mode", "Categorized by Engine Type");
        drawLegend(typeColors, "Engine Type");
        
        // Transition colors to engine type
        nodes.transition().duration(800)
            .attr("fill", d => typeColors(d.type || "Petrol"));

        if (step === 1) {
            updateUI("Showroom Grid", "Grouped by Manufacturer");
            makes.forEach(m => {
                var c = gridCenters[m];
                gridLayer.append("rect")
                    .attr("x", c.x - c.w/2).attr("y", c.y - c.h/2)
                    .attr("width", c.w).attr("height", c.h)
                    .attr("stroke", "#444").attr("fill", "rgba(255,255,255,0.05)")
                    .style("opacity", 0).transition().duration(1000).style("opacity", 1);
                
                drawLabel(m, c.x, c.y - c.h/2 - 12, "middle", "#fff");
            });

            simulation
                .force('x', d3.forceX().strength(0.35).x(d => gridCenters[d.make].x))
                .force('y', d3.forceY().strength(0.35).y(d => gridCenters[d.make].y));
        } 
        else if (step === 2) {
            updateUI("0-100 km/h", "Acceleration Performance");
            drawAxisLine("y", 150, height-50, width/2);
            drawLabel("2.0s", width/2 + 20, 160, "start", "#ff2400");
            drawLabel("5.0s+", width/2 + 20, height-60, "start", "#999");

            simulation
                .force('x', d3.forceX().strength(0.08).x(width/2))
                .force('y', d3.forceY().strength(0.25).y(d => performanceScale(num(d.performance))));
        } 
        else if (step === 3) {
            updateUI("Power to Weight", "Mass vs Horsepower");
            drawAxis(d3.axisBottom(massScale).ticks(5), 0, height-40);
            drawAxis(d3.axisLeft(hpScale).ticks(5), 50, 0);

            simulation
                .force('x', d3.forceX().strength(0.2).x(d => massScale(num(d.mass))))
                .force('y', d3.forceY().strength(0.2).y(d => hpScale(num(d.horsepower))));
        }
    }
}

// Helpers
function updateUI(title, sub) {
    sceneTitle.text(title);
    storyText.text(sub);
}
function drawLabel(txt, x, y, anchor, col) {
    axisLayer.append("text").attr("x", x).attr("y", y).text(txt)
        .attr("text-anchor", anchor).style("font-family", "'Exo 2'").style("font-style", "italic")
        .style("fill", col).style("font-weight", "700").style("font-size", "14px")
        .style("opacity",0).transition().style("opacity",1);
}
function drawAxisLine(type, start, end, fixed) {
    axisLayer.append("line")
        .attr("x1", type==='y'?fixed:start).attr("y1", type==='y'?start:fixed)
        .attr("x2", type==='y'?fixed:end).attr("y2", type==='y'?end:fixed)
        .attr("stroke", "#555").attr("stroke-dasharray", "4");
}
function drawAxis(axis, x, y) {
    var g = axisLayer.append("g").attr("transform", `translate(${x},${y})`).call(axis);
    g.selectAll("text").style("fill", "#999").style("font-family", "'Exo 2'");
    g.selectAll("line, path").style("stroke", "#555");
}

var currentStep = 0;
svg.on("click", function() {
    currentStep = (currentStep + 1) % 4;
    drawStep(currentStep);
});