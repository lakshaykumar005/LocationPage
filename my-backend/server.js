const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const port = 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());

const filePath = path.join(__dirname, 'userData.json');

// Endpoint to save user data
app.post('/save-location', (req, res) => {
  const newUserData = req.body;

  // Read existing data
  fs.readFile(filePath, 'utf8', (err, data) => {
    let existingData = [];

    if (!err && data) {
      try {
        existingData = JSON.parse(data);
        if (!Array.isArray(existingData)) {
          existingData = [];
        }
      } catch (parseError) {
        console.error('Error parsing JSON:', parseError);
        return res.status(500).send('Error reading existing data');
      }
    }

    // Append new data
    existingData.push(newUserData);

    // Write updated data back to file
    fs.writeFile(filePath, JSON.stringify(existingData, null, 2), (err) => {
      if (err) {
        console.error('Error saving file:', err);
        return res.status(500).send('Error saving data');
      }
      console.log('Data added successfully');
      res.status(200).send('Data added successfully');
    });
  });
});

// Start the server
app.listen(port, () => {
  console.log(`Server running on http://localhost:${port}`);
});
