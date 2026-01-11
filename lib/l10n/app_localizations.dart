import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr')
  ];

  /// The title of the application
  ///
  /// In en, this message translates to:
  /// **'SplitBalance'**
  String get appTitle;

  /// Label for Bills navigation and screen
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get bills;

  /// Label for Payment Splits & Categories navigation
  ///
  /// In en, this message translates to:
  /// **'Splits & Categories'**
  String get splitsAndCategories;

  /// Label for Summary navigation and screen
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// Label for Settings navigation
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Title for adding a new bill
  ///
  /// In en, this message translates to:
  /// **'Add Bill'**
  String get addBill;

  /// Title for editing a bill
  ///
  /// In en, this message translates to:
  /// **'Edit Bill'**
  String get editBill;

  /// Title for delete bill dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Bill'**
  String get deleteBill;

  /// Confirmation message for deleting a bill
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this bill?'**
  String get areYouSureDeleteBill;

  /// Cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Delete button label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Edit button label
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Add button label
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Button label for refresh action
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Tooltip for add bill button
  ///
  /// In en, this message translates to:
  /// **'Add Bill'**
  String get addBillTooltip;

  /// Tooltip for refresh button
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshTooltip;

  /// Error message prefix
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String error(String error);

  /// Message when there are no bills
  ///
  /// In en, this message translates to:
  /// **'No bills yet'**
  String get noBillsYet;

  /// Button to add first bill
  ///
  /// In en, this message translates to:
  /// **'Add Your First Bill'**
  String get addYourFirstBill;

  /// Generic bill label
  ///
  /// In en, this message translates to:
  /// **'Bill'**
  String get bill;

  /// Date label
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// Amount label
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// Label for who paid the bill
  ///
  /// In en, this message translates to:
  /// **'Paid by'**
  String get paidBy;

  /// Category label
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// Validation message for paid by selection
  ///
  /// In en, this message translates to:
  /// **'Please select who paid'**
  String get selectWhoPaid;

  /// Validation message for category selection
  ///
  /// In en, this message translates to:
  /// **'Please select a category'**
  String get selectCategory;

  /// Validation message for amount
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get enterValidAmount;

  /// Details label for bill
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// Title for folder selection dialog
  ///
  /// In en, this message translates to:
  /// **'Select Storage Folder'**
  String get selectStorageFolder;

  /// Message when folder is selected
  ///
  /// In en, this message translates to:
  /// **'Folder selected! Checking folder data...'**
  String get folderSelected;

  /// Title for sign out confirmation
  ///
  /// In en, this message translates to:
  /// **'Sign Out?'**
  String get signOut;

  /// Sign out confirmation message
  ///
  /// In en, this message translates to:
  /// **'Do you want to sign out? You can sign back in later.'**
  String get signOutConfirmation;

  /// Sign out button label
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOutButton;

  /// Label for refresh folders button
  ///
  /// In en, this message translates to:
  /// **'Refresh Folders'**
  String get refreshFolders;

  /// Title for person names dialog
  ///
  /// In en, this message translates to:
  /// **'Enter Person Names'**
  String get enterPersonNames;

  /// Prompt message for entering person names
  ///
  /// In en, this message translates to:
  /// **'Please enter the names of the two people for this folder:'**
  String get enterPersonNamesPrompt;

  /// Message when folder has different person names
  ///
  /// In en, this message translates to:
  /// **'The folder contains data with different person names. Please enter the correct names:'**
  String get folderContainsDifferentNames;

  /// Label for person 1 name field
  ///
  /// In en, this message translates to:
  /// **'Person 1 Name'**
  String get person1Name;

  /// Label for person 2 name field
  ///
  /// In en, this message translates to:
  /// **'Person 2 Name'**
  String get person2Name;

  /// Hint for person 1 name field
  ///
  /// In en, this message translates to:
  /// **'Enter first person\'s name'**
  String get enterFirstName;

  /// Hint for person 2 name field
  ///
  /// In en, this message translates to:
  /// **'Enter second person\'s name'**
  String get enterSecondName;

  /// Validation message for person names
  ///
  /// In en, this message translates to:
  /// **'Please enter both person names'**
  String get enterBothPersonNames;

  /// Button to change folder
  ///
  /// In en, this message translates to:
  /// **'Change Folder'**
  String get changeFolder;

  /// Title for create categories dialog
  ///
  /// In en, this message translates to:
  /// **'Create Categories'**
  String get createCategories;

  /// Prompt message for creating categories
  ///
  /// In en, this message translates to:
  /// **'You need to create at least one category before you can add bills.\n\nPlease go to the \"Splits & Categories\" tab in the bottom navigation to create categories.'**
  String get createCategoriesPrompt;

  /// Button to change person names
  ///
  /// In en, this message translates to:
  /// **'Change Person Names'**
  String get changePersonNames;

  /// Button to navigate to categories
  ///
  /// In en, this message translates to:
  /// **'Go to Categories'**
  String get goToCategories;

  /// Message when action requires sign in
  ///
  /// In en, this message translates to:
  /// **'Please sign in first'**
  String get pleaseSignInFirst;

  /// Error message when loading folders
  ///
  /// In en, this message translates to:
  /// **'Error loading folders: {error}'**
  String errorLoadingFolders(String error);

  /// Title for create folder dialog
  ///
  /// In en, this message translates to:
  /// **'Create New Folder'**
  String get createNewFolder;

  /// Success message when folder is created
  ///
  /// In en, this message translates to:
  /// **'Folder \"{folderName}\" created successfully'**
  String folderCreatedSuccessfully(String folderName);

  /// Error message when creating folder
  ///
  /// In en, this message translates to:
  /// **'Error creating folder: {error}'**
  String errorCreatingFolder(String error);

  /// Success message when config is saved
  ///
  /// In en, this message translates to:
  /// **'Configuration saved successfully'**
  String get configSaved;

  /// Error message when saving config
  ///
  /// In en, this message translates to:
  /// **'Error saving config: {error}'**
  String errorSavingConfig(String error);

  /// Title for configuration screen
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get configuration;

  /// Title for sign in required message
  ///
  /// In en, this message translates to:
  /// **'Sign in required'**
  String get signInRequired;

  /// Message about sign in requirement
  ///
  /// In en, this message translates to:
  /// **'Please sign in with your Google account to access all features of SplitBalance.'**
  String get signInRequiredMessage;

  /// Button label for Google sign in
  ///
  /// In en, this message translates to:
  /// **'Sign In with Google'**
  String get signInWithGoogle;

  /// Title for folder selection required message
  ///
  /// In en, this message translates to:
  /// **'Folder Selection Required'**
  String get folderSelectionRequired;

  /// Message about folder selection requirement
  ///
  /// In en, this message translates to:
  /// **'Please select a Google Drive folder to store your data.'**
  String get folderSelectionRequiredMessage;

  /// Title for person names required message
  ///
  /// In en, this message translates to:
  /// **'Person Names Required'**
  String get personNamesRequired;

  /// Message about person names requirement
  ///
  /// In en, this message translates to:
  /// **'Please enter the names of both people using this folder.'**
  String get personNamesRequiredMessage;

  /// Button label to navigate to folder
  ///
  /// In en, this message translates to:
  /// **'Navigate to Folder'**
  String get navigateToFolder;

  /// Loading indicator text
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Loading path message
  ///
  /// In en, this message translates to:
  /// **'Loading path...'**
  String get loadingPath;

  /// Create button label
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Label for My Drive root folder
  ///
  /// In en, this message translates to:
  /// **'My Drive'**
  String get myDrive;

  /// Label for unnamed folder
  ///
  /// In en, this message translates to:
  /// **'Unnamed'**
  String get unnamed;

  /// Message when folder is selected and saved
  ///
  /// In en, this message translates to:
  /// **'Folder \"{folderName}\" selected and saved. Checking folder data...'**
  String folderSelectedAndSaved(String folderName);

  /// Hint when folder is not selected
  ///
  /// In en, this message translates to:
  /// **'Select a folder first'**
  String get selectFolderFirst;

  /// Tip message when folder is not selected for person names section
  ///
  /// In en, this message translates to:
  /// **'Please select a folder first to enter person names'**
  String get selectFolderFirstToEnterPersonNames;

  /// Helper text when folder is required
  ///
  /// In en, this message translates to:
  /// **'Folder must be selected'**
  String get folderMustBeSelected;

  /// Theme label
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// Light theme name
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// Dark theme name
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// Pink theme name
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get pink;

  /// Language label
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// English language name
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// French language name
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get french;

  /// Title for clear all config dialog
  ///
  /// In en, this message translates to:
  /// **'Clear All Configuration?'**
  String get clearAllConfiguration;

  /// Message for clearing all configuration
  ///
  /// In en, this message translates to:
  /// **'This will:\n\n• Sign out from Google\n• Clear folder selection\n• Clear person names\n• Clear all saved settings\n\nThis action cannot be undone.'**
  String get clearAllConfigMessage;

  /// Button label for clear all configuration
  ///
  /// In en, this message translates to:
  /// **'Clear All Configuration'**
  String get clearAllConfigurationButton;

  /// Button label to clear all config
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAll;

  /// Success message when config is cleared
  ///
  /// In en, this message translates to:
  /// **'All configuration cleared'**
  String get allConfigCleared;

  /// Button label to calculate balances
  ///
  /// In en, this message translates to:
  /// **'Calculate Balances'**
  String get calculateBalances;

  /// Button label to add payment split
  ///
  /// In en, this message translates to:
  /// **'Add Payment Split'**
  String get addPaymentSplit;

  /// Title for editing payment split
  ///
  /// In en, this message translates to:
  /// **'Edit Payment Split'**
  String get editPaymentSplit;

  /// Label for start date
  ///
  /// In en, this message translates to:
  /// **'Start Date'**
  String get startDate;

  /// Label for end date
  ///
  /// In en, this message translates to:
  /// **'End Date'**
  String get endDate;

  /// Label for all categories option
  ///
  /// In en, this message translates to:
  /// **'All Categories'**
  String get allCategories;

  /// Label for person percentage
  ///
  /// In en, this message translates to:
  /// **'{personName} Percentage'**
  String personPercentage(String personName);

  /// Display for person percentage
  ///
  /// In en, this message translates to:
  /// **'{personName} Percentage: {percentage}%'**
  String personPercentageDisplay(String personName, String percentage);

  /// Display format for payment split person
  ///
  /// In en, this message translates to:
  /// **'{personName}: {percentage}%'**
  String paymentSplitPersonDisplay(String personName, String percentage);

  /// Title for delete payment split dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Payment Split'**
  String get deletePaymentSplit;

  /// Confirmation message for deleting payment split
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this payment split?'**
  String get deletePaymentSplitMessage;

  /// Message when there are no payment splits
  ///
  /// In en, this message translates to:
  /// **'No payment splits yet'**
  String get noPaymentSplits;

  /// Message when there are no categories
  ///
  /// In en, this message translates to:
  /// **'No categories yet'**
  String get noCategories;

  /// Button label to add category
  ///
  /// In en, this message translates to:
  /// **'Add Category'**
  String get addCategory;

  /// Title for editing category
  ///
  /// In en, this message translates to:
  /// **'Edit Category'**
  String get editCategory;

  /// Title for delete category dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Category'**
  String get deleteCategory;

  /// Confirmation message for deleting category
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{categoryName}\"?'**
  String deleteCategoryMessage(String categoryName);

  /// Error message when trying to delete category in use
  ///
  /// In en, this message translates to:
  /// **'Cannot delete category that is in use'**
  String get categoryInUse;

  /// Subtitle explaining why category cannot be deleted
  ///
  /// In en, this message translates to:
  /// **'This category is being used by bills or payment splits. Please remove or change them first.'**
  String get categoryInUseSubtitle;

  /// Validation message for category name
  ///
  /// In en, this message translates to:
  /// **'Please enter a category name'**
  String get enterCategoryName;

  /// Dismiss button label
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// Tab label for Payment Splits
  ///
  /// In en, this message translates to:
  /// **'Payment Splits'**
  String get paymentSplits;

  /// Tab label for Categories
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// Tooltip for recalculate button
  ///
  /// In en, this message translates to:
  /// **'Recalculate'**
  String get recalculate;

  /// Message when no balance is calculated
  ///
  /// In en, this message translates to:
  /// **'No balance calculated'**
  String get noBalanceCalculated;

  /// Message when balance is zero
  ///
  /// In en, this message translates to:
  /// **'All Balanced!'**
  String get allBalanced;

  /// Label for net balance
  ///
  /// In en, this message translates to:
  /// **'Net Balance'**
  String get netBalance;

  /// Label for amount paid
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// Label for expected amount
  ///
  /// In en, this message translates to:
  /// **'Expected'**
  String get expected;

  /// Label for difference amount
  ///
  /// In en, this message translates to:
  /// **'Difference'**
  String get difference;

  /// Label for category breakdown section
  ///
  /// In en, this message translates to:
  /// **'Category Breakdown'**
  String get categoryBreakdown;

  /// Label for statistics section
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// Label for total bills count
  ///
  /// In en, this message translates to:
  /// **'Total Bills'**
  String get totalBills;

  /// Label for total amount
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get totalAmount;

  /// Button label to save bill
  ///
  /// In en, this message translates to:
  /// **'Save Bill'**
  String get saveBill;

  /// Validation message for amount field
  ///
  /// In en, this message translates to:
  /// **'Please enter an amount'**
  String get enterAmount;

  /// Label for optional details field
  ///
  /// In en, this message translates to:
  /// **'Details (optional)'**
  String get detailsOptional;

  /// Message when no categories are available
  ///
  /// In en, this message translates to:
  /// **'No categories available. Please add categories in the Payment Splits & Categories screen.'**
  String get noCategoriesAvailable;

  /// Error message when saving bill fails
  ///
  /// In en, this message translates to:
  /// **'Error saving bill: {error}'**
  String errorSavingBill(String error);

  /// Preposition for date ranges
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get to;

  /// Hint message for adding categories
  ///
  /// In en, this message translates to:
  /// **'Add categories to organize your bills'**
  String get addCategoriesToOrganize;

  /// Label for category in use
  ///
  /// In en, this message translates to:
  /// **'In use (cannot delete)'**
  String get inUseCannotDelete;

  /// Label for Google Drive connection section
  ///
  /// In en, this message translates to:
  /// **'Google Drive Connection'**
  String get googleDriveConnection;

  /// Label for Google Drive folder section
  ///
  /// In en, this message translates to:
  /// **'Google Drive Folder'**
  String get googleDriveFolder;

  /// Prompt message for selecting Google Drive folder in dialog
  ///
  /// In en, this message translates to:
  /// **'Please select a Google Drive folder where your data will be stored:'**
  String get selectGoogleDriveFolderPrompt;

  /// Message explaining Google Drive folder requirement
  ///
  /// In en, this message translates to:
  /// **'Please select a Google Drive folder where your data will be stored. You must select a folder before accessing other features.'**
  String get selectGoogleDriveFolderMessage;

  /// Section header for Person Names
  ///
  /// In en, this message translates to:
  /// **'Person Names'**
  String get personNames;

  /// Label for folder selection/navigation prompt
  ///
  /// In en, this message translates to:
  /// **'Select or navigate into a folder:'**
  String get selectOrNavigateFolder;

  /// Button label to save configuration
  ///
  /// In en, this message translates to:
  /// **'Save Configuration'**
  String get saveConfiguration;

  /// Tooltip for go back button in folder navigation
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// Tooltip for navigate into folder button
  ///
  /// In en, this message translates to:
  /// **'Navigate into folder'**
  String get navigateIntoFolder;

  /// Tooltip for select folder button
  ///
  /// In en, this message translates to:
  /// **'Select this folder'**
  String get selectThisFolder;

  /// Message when balance is zero and no one owes anyone
  ///
  /// In en, this message translates to:
  /// **'All balanced! No one owes anyone.'**
  String get allBalancedNoOneOwes;

  /// Message when one person owes another
  ///
  /// In en, this message translates to:
  /// **'{person1} owes {person2} {amount}'**
  String personOwesPerson(String person1, String person2, String amount);

  /// Label for the currently selected folder section
  ///
  /// In en, this message translates to:
  /// **'Currently Used Folder:'**
  String get currentlyUsedFolder;

  /// Label for folder name input field
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get folderName;

  /// Hint text for folder name input field
  ///
  /// In en, this message translates to:
  /// **'Enter folder name'**
  String get enterFolderName;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
