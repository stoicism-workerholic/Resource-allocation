import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'House Resources Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue).copyWith(
          secondary: Colors.greenAccent,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: Colors.black54),
          bodyMedium: TextStyle(color: Colors.black54),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ResourcesPage(),
    );
  }
}

class ResourcesPage extends StatefulWidget {
  const ResourcesPage({super.key});

  @override
  ResourcesPageState createState() => ResourcesPageState();
}

class ResourcesPageState extends State<ResourcesPage> {
  String? _selectedProfile;
  String? _selectedResource;

  // List of profiles
  final List<String> profiles = [
    'Adithya',
    'Jayadeep',
    'Srinivas',
    'Prakash',
    'Dinesh',
    'Prudhvi',
    'Bharadwaj',
  ];

  final Map<String, double> _resourceAmounts = {}; // Use double to handle resource amounts
  final Map<String, double> _usage = {};
  final Map<String, Map<String, double>> _profileUsageDetails = {};

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _newResourceController = TextEditingController();
  final TextEditingController _resourceAmountController = TextEditingController();
  final ScrollController _userViewScrollController = ScrollController();
  final ScrollController _adminViewScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchResourcesFromFirestore();
    _fetchUsageFromFirestore();
  }

  Future<void> _fetchResourcesFromFirestore() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('resources').get();
      snapshot.docs.forEach((doc) {
        String resource = doc.get('name');
        double amount = doc.get('amount').toDouble(); // Ensure it's a double

        _resourceAmounts[resource] = amount; // Store as double
        // Initialize usage details for each profile
        for (var profile in profiles) {
          if (_profileUsageDetails[profile] == null) {
            _profileUsageDetails[profile] = {};
          }
          _profileUsageDetails[profile]![resource] = 0; // Initialize resource amount to 0 for each profile
        }
      });
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch resources: $e')),
      );
    }
  }

  Future<void> _fetchUsageFromFirestore() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('usage').get();
      snapshot.docs.forEach((doc) {
        String profile = doc.get('profile');
        String resource = doc.get('resource');
        double amount = doc.get('amount');

        if (_profileUsageDetails[profile] == null) {
          _profileUsageDetails[profile] = {};
        }
        _profileUsageDetails[profile]![resource] = (_profileUsageDetails[profile]![resource] ?? 0) + amount;
        _usage[profile] = (_usage[profile] ?? 0) + amount;
      });
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch usage data: $e')),
      );
    }
  }

  @override
  void dispose() {
    _userViewScrollController.dispose();
    _adminViewScrollController.dispose();
    super.dispose();
  }

  void _updateResource(String resource, double amount) {
    setState(() {
      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount must be positive.')),
        );
        return;
      }

      if (_resourceAmounts.containsKey(resource)) {
        if (amount > _resourceAmounts[resource]!) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Insufficient resources available for $resource.')),
          );
          return; // Prevent transaction if insufficient resources
        }

        _resourceAmounts[resource] = (_resourceAmounts[resource] ?? 0) - amount;
        if (_resourceAmounts[resource]! < 0) {
          _resourceAmounts[resource] = 0;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Resource amount cannot be negative.')),
          );
        } else {
          if (_selectedProfile != null) {
            final profileKey = _selectedProfile!;
            if (_profileUsageDetails[profileKey] == null) {
              _profileUsageDetails[profileKey] = {};
            }
            _profileUsageDetails[profileKey]![resource] = (_profileUsageDetails[profileKey]![resource] ?? 0) + amount;
            _usage[profileKey] = (_usage[profileKey] ?? 0) + amount;

            // Save to Firestore
            _saveUsageToFirestore(profileKey, resource, amount);
            // Update the resource in Firestore
            _updateResourceInFirestore(resource);
          }
        }
      }
    });
  }

  void _saveUsageToFirestore(String profile, String resource, double amount) async {
    try {
      await FirebaseFirestore.instance.collection('usage').add({
        'profile': profile,
        'resource': resource,
        'amount': amount,
        'timestamp': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transaction updated for $profile: $amount units of $resource')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save usage data: $e')),
      );
    }
  }

  void _updateResourceInFirestore(String resource) async {
    try {
      // Check if the document exists
      QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('resources').where('name', isEqualTo: resource).get();
      if (snapshot.docs.isNotEmpty) {
        // Add the new amount to the existing amount in Firestore
        double newAmount = (_resourceAmounts[resource] ?? 0);
        await FirebaseFirestore.instance.collection('resources').doc(snapshot.docs.first.id).update({
          'amount': newAmount,
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resource document not found in Firestore: $resource')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update resource in Firestore: $e')),
      );
    }
  }

  void _addNewResource() {
    final newResource = _newResourceController.text.trim();
    if (newResource.isNotEmpty) {
      setState(() {
        if (!_resourceAmounts.containsKey(newResource)) {
          _resourceAmounts[newResource] = 0;
          // Add new resource to Firestore
          FirebaseFirestore.instance.collection('resources').add({
            'name': newResource,
            'amount': 0,
          });
          // Initialize usage details for the new resource for each profile
          for (var profile in profiles) {
            if (_profileUsageDetails[profile] == null) {
              _profileUsageDetails[profile] = {};
            }
            _profileUsageDetails[profile]![newResource] = 0; // Initialize new resource amount to 0 for each profile
          }
          _newResourceController.clear();
        }
      });
    }
  }

  void _updateResourceAmount() {
    final resource = _selectedResource;
    final amount = double.tryParse(_resourceAmountController.text.trim());
    if (resource != null && amount != null && amount >= 0) {
      setState(() {
        // Add the new amount to the existing amount
        _resourceAmounts[resource] = (_resourceAmounts[resource] ?? 0) + amount;
        // Update resource amount in Firestore
        _updateResourceInFirestore(resource);
        _resourceAmountController.clear();
      });
    }
  }

  void _resetProfileResources() {
    final profileKey = _selectedProfile;
    if (profileKey != null) {
      setState(() {
        _profileUsageDetails[profileKey]?.forEach((key, _) {
          _profileUsageDetails[profileKey]![key] = (_profileUsageDetails[profileKey]![key] ?? 0) + (_profileUsageDetails[profileKey]![key] ?? 0);
        });
        _usage[profileKey] = (_usage[profileKey] ?? 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('House Resources Tracker'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'User View'),
              Tab(text: 'Admin View'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // User View
            Scrollbar(
              controller: _userViewScrollController,
              child: SingleChildScrollView(
                controller: _userViewScrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 120,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _resourceAmounts.entries.map((entry) {
                            return Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 120,
                              child: Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                color: Colors.blueAccent,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.local_drink,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                      Text(
                                        '${entry.key}\n${entry.value.toStringAsFixed(0)} units',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButton(
                            value: _selectedProfile,
                            hint: const Text('Select Profile'),
                            items: profiles.map((profile) {
                              return DropdownMenuItem(
                                value: profile,
                                child: Row(
                                  children: [
                                    const Icon(Icons.person),
                                    const SizedBox(width: 10),
                                    Text(profile),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedProfile = value;
                                _selectedResource = null;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          if (_selectedProfile != null) ...[
                            DropdownButton(
                              value: _selectedResource,
                              hint: const Text('Select Resource'),
                              items: _resourceAmounts.keys.map((resource) {
                                return DropdownMenuItem(
                                  value: resource,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.local_fire_department),
                                      const SizedBox(width: 10),
                                      Text(resource),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedResource = value;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            if (_selectedResource != null) ...[
                              TextField(
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Amount Used',
                                  hintText: 'Enter amount used in units',
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.check),
                                    onPressed: () {
                                      double? amount = double.tryParse(_amountController.text);
                                      if (amount != null && amount > 0) {
                                        _updateResource(_selectedResource!, amount);
                                        _amountController.clear();
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Please enter a valid positive number.')),
                                        );
                                      }
                                    },
                                  ),
                                ),
                                controller: _amountController,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 150,
                                child: ListView(
                                  children: _usage.entries.map((entry) {
                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 8),
                                      elevation: 4,
                                      child: ListTile(
                                        leading: const Icon(Icons.show_chart),
                                        title: Text(entry.key),
                                        subtitle: Text('${entry.value.toStringAsFixed(0)} units used'),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    Container(
                      height: 200,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: profiles.map((profile) {
                            final usageDetails = _profileUsageDetails[profile] ?? {};
                            return Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 250,
                              child: Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                color: Colors.greenAccent,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        profile,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: ListView(
                                        children: usageDetails.entries.map((entry) {
                                          return ListTile(
                                            leading: const Icon(Icons.local_offer),
                                            title: Text(
                                              '${entry.key}: ${entry.value.toStringAsFixed(0)} units',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 14,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Admin View
            Scrollbar(
              controller: _adminViewScrollController,
              child: SingleChildScrollView(
                controller: _adminViewScrollController,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Panel',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _newResourceController,
                      decoration: const InputDecoration(
                        labelText: 'New Resource',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _addNewResource,
                      child: const Text('Add Resource'),
                    ),
                    const SizedBox(height: 20),
                    DropdownButton(
                      value: _selectedResource,
                      hint: const Text('Select Resource to Update'),
                      items: _resourceAmounts.keys.map((resource) {
                        return DropdownMenuItem(
                          value: resource,
                          child: Row(
                            children: [
                              const Icon(Icons.local_fire_department),
                              const SizedBox(width: 10),
                              Text(resource),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedResource = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _resourceAmountController,
                      decoration: const InputDecoration(
                        labelText: 'New Amount',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _updateResourceAmount,
                      child: const Text('Update Resource Amount'),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _resetProfileResources,
                      child: const Text('Reset Profile Resources'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}